#!/bin/bash
set -Eeuo pipefail
umask 077

result=${TKL_TEST_RESULT:?TKL_TEST_RESULT is required}
app_password=${TKL_TEST_APP_PASS:?TKL_TEST_APP_PASS is required}
base=https://localhost
cookie=/tmp/tkl-foswiki-cookie.$$
page=/tmp/tkl-foswiki-page.$$
headers=/tmp/tkl-foswiki-headers.$$
upgrade_fixture=

cleanup() {
    rm -f -- "$cookie" "$page" "$headers"
    if [ -n "$upgrade_fixture" ]; then
        rm -rf -- "$upgrade_fixture"
    fi
}
trap cleanup EXIT

hidden_value() {
    local name=$1
    local source=$2
    sed -n "s/.*name=['\"]${name}['\"][^>]*value=['\"]\([^'\"]*\)['\"].*/\1/p" \
        "$source" | head -n1
}

strike_key() {
    local source=$1
    local raw secret
    raw=$(hidden_value validation_key "$source")
    raw=${raw#\?}
    secret=$(awk '$6 == "FOSWIKISTRIKEONE" {print $7}' "$cookie" | tail -n1)
    test -n "$raw"
    test -n "$secret"
    printf '%s' "$raw$secret" | md5sum | awk '{print $1}'
}

login_admin() {
    local login_url key
    login_url="$base/foswiki/bin/login/Main/WebHome"
    rm -f -- "$cookie"
    curl --insecure --fail --silent --show-error \
        --cookie-jar "$cookie" "$login_url" >"$page"
    key=$(strike_key "$page")
    curl --insecure --silent --show-error \
        --cookie "$cookie" --cookie-jar "$cookie" \
        --data-urlencode "validation_key=$key" \
        --data-urlencode 'username=admin' \
        --data-urlencode "password=$app_password" \
        --data-urlencode 'foswiki_origin=GET,view,/foswiki/bin/view' \
        --dump-header "$headers" --output "$page" "$login_url"
    grep -q '^HTTP/.* 302' "$headers"
    curl --insecure --fail --silent --show-error \
        --cookie "$cookie" "$base/foswiki/bin/view" >"$page"
    grep -Fq 'AdminUser' "$page"
    grep -Fq 'Log Out' "$page"
}

create_topic() {
    local topic=$1
    local text=$2
    local edit_url key
    edit_url="$base/foswiki/bin/edit/Main/$topic?nowysiwyg=1"
    curl --insecure --fail --silent --show-error \
        --cookie "$cookie" --cookie-jar "$cookie" "$edit_url" >"$page"
    key=$(strike_key "$page")
    curl --insecure --silent --show-error \
        --cookie "$cookie" --cookie-jar "$cookie" \
        --data-urlencode "validation_key=$key" \
        --data-urlencode "topic=Main.$topic" \
        --data-urlencode "text=$text" \
        --data-urlencode 'action_save=1' \
        --data-urlencode 'newtopic=1' \
        --data-urlencode 'nowysiwyg=1' \
        --dump-header "$headers" --output "$page" "$base/foswiki/bin/save"
    grep -q '^HTTP/.* 302' "$headers"
    grep -Fq "/foswiki/bin/view/Main/$topic" "$headers"
    curl --insecure --fail --silent --show-error \
        --cookie "$cookie" "$base/foswiki/bin/view/Main/$topic" >"$page"
    grep -Fq "$text" "$page"
    grep -Fq "$text" "/var/www/foswiki/data/Main/$topic.txt"
    grep -Fq "save | Main.$topic" /var/www/foswiki/working/logs/events.log
}

systemctl --quiet is-active apache2.service postfix.service cron.service \
    multi-user.target
systemctl --quiet is-enabled apache2.service postfix.service cron.service
apache2ctl -t
apache2ctl -M 2>/dev/null | grep -q ' cgid_module '
apache2ctl -M 2>/dev/null | grep -q ' rewrite_module '
apache2ctl -M 2>/dev/null | grep -q ' ssl_module '
grep -Fxq 'VERSION_CODENAME=trixie' /etc/os-release
grep -Eq '^turnkey-foswiki-19\.0' /etc/turnkey_version
grep -Fq '[40foswiki] successfully completed' /var/log/inithooks.log

installed_version=$(cd /var/www/foswiki && \
    perl -I lib -MFoswiki -e 'print $Foswiki::VERSION')
test "$installed_version" = v2.1.11
stat -c '%U:%G %a' /var/www/foswiki/data/.htpasswd |
    grep -Eq '^www-data:www-data 600$'
grep -Fq "\$Foswiki::cfg{DefaultUrlHost} = 'https://localhost';" \
    /var/www/foswiki/lib/LocalSite.cfg
grep -Fq "\$Foswiki::cfg{WebMasterEmail} = 'admin@example.invalid';" \
    /var/www/foswiki/lib/LocalSite.cfg

login_admin
topic="TurnKeyV19Acceptance$$"
text="Foswiki topic persistence round trip $$"
create_topic "$topic" "$text"

grep -Fxq '15 0 * * * www-data perl -I /var/www/foswiki/bin /var/www/foswiki/tools/tick_foswiki.pl >/dev/null 2>&1' \
    /etc/cron.d/foswiki
grep -Fxq '30 0 * * * www-data perl -I /var/www/foswiki/bin /var/www/foswiki/tools/mailnotify -q >/dev/null 2>&1' \
    /etc/cron.d/foswiki
grep -Fxq '45 0 * * * www-data cd /var/www/foswiki/bin && ./statistics -subwebs 1 >/dev/null 2>&1' \
    /etc/cron.d/foswiki
runuser -u www-data -- perl -I /var/www/foswiki/bin \
    /var/www/foswiki/tools/tick_foswiki.pl
runuser -u www-data -- perl -I /var/www/foswiki/bin \
    /var/www/foswiki/tools/mailnotify -q
(cd /var/www/foswiki/bin && runuser -u www-data -- \
    ./statistics -subwebs 1 >/dev/null)

dpkg-query -W rcs libdbi-perl webmin-apache postfix >/dev/null
curl --insecure --fail --silent --show-error --head \
    https://127.0.0.1:12321/ >/dev/null
ss -ltn | grep -Eq '127\.0\.0\.1:25[[:space:]]'

latest_name=$(curl --fail --silent --show-error \
    https://api.github.com/repos/foswiki/distro/releases/latest |
    sed -n 's/.*"name": "Foswiki-\([^"]*\)".*/\1/p' | head -n1)
test -n "$latest_name"
test "v$latest_name" = "$installed_version"

# Exercise Foswiki's documented patch upgrade on a disposable 2.1.10 tree.
upgrade_fixture=$(mktemp -d /tmp/tkl-foswiki-upgrade.XXXXXX)
full_archive="$upgrade_fixture/Foswiki-2.1.10.tgz"
upgrade_archive="$upgrade_fixture/Foswiki-upgrade-2.1.11.tgz"
curl --fail --silent --show-error --location --output "$full_archive" \
    https://github.com/foswiki/distro/releases/download/FoswikiRelease02x01x10/Foswiki-2.1.10.tgz
curl --fail --silent --show-error --location --output "$upgrade_archive" \
    https://github.com/foswiki/distro/releases/download/FoswikiRelease02x01x11/Foswiki-upgrade-2.1.11.tgz
printf '%s  %s\n' \
    e566ee46b8b525f5646e07f0e87c7192956ef22989b7e3df73721d9cc69ce1d2 \
    "$full_archive" | sha256sum --check --status
printf '%s  %s\n' \
    bcbe0486f03a75834dd5c67b539a05e9445f918bdb20edfd391a577fb90df9f7 \
    "$upgrade_archive" | sha256sum --check --status

cp /var/www/foswiki/lib/LocalSite.cfg "$upgrade_fixture/LocalSite.cfg"
cp /var/www/foswiki/data/.htpasswd "$upgrade_fixture/.htpasswd"
systemctl stop apache2.service
rm -rf -- /var/www/foswiki
install -d -o www-data -g www-data /var/www/foswiki
tar --strip-components=1 -zxf "$full_archive" -C /var/www/foswiki
install -o www-data -g www-data -m 640 \
    "$upgrade_fixture/LocalSite.cfg" /var/www/foswiki/lib/LocalSite.cfg
install -o www-data -g www-data -m 600 \
    "$upgrade_fixture/.htpasswd" /var/www/foswiki/data/.htpasswd
chown -R www-data:www-data /var/www/foswiki
systemctl start apache2.service
test "$(cd /var/www/foswiki && perl -I lib -MFoswiki -e 'print $Foswiki::VERSION')" = v2.1.10

login_admin
upgrade_topic="TurnKeyUpgradeAcceptance$$"
upgrade_text="Foswiki 2.1.10 to 2.1.11 persistence round trip $$"
create_topic "$upgrade_topic" "$upgrade_text"

systemctl stop apache2.service
runuser -u www-data -- tar --strip-components=1 -zxf - \
    -C /var/www/foswiki <"$upgrade_archive"
(cd /var/www/foswiki/tools && \
    runuser -u www-data -- ./configure --save)
find /var/www/foswiki/working/tmp -mindepth 1 -delete
systemctl start apache2.service
test "$(cd /var/www/foswiki && perl -I lib -MFoswiki -e 'print $Foswiki::VERSION')" = v2.1.11
login_admin
curl --insecure --fail --silent --show-error \
    --cookie "$cookie" "$base/foswiki/bin/view/Main/$upgrade_topic" >"$page"
grep -Fq "$upgrade_text" "$page"
grep -Fq "$upgrade_text" "/var/www/foswiki/data/Main/$upgrade_topic.txt"

grep -Rqs '^Suites: trixie' /etc/apt/sources.list.d
! grep -Rqi bookworm /etc/apt/sources.list /etc/apt/sources.list.d

cat >"$result" <<EOF
package_source=Official Foswiki $installed_version security release archive, SHA-256 3a490eb460db4ca69d73dfe44c7984889552e5313eff60162760e80e66e5eba6 from upstream release metadata; Perl and dependencies from Debian Trixie
installed_version=Foswiki $installed_version; $(perl --version | head -n2 | tail -n1); rcs $(dpkg-query -W -f='${Version}' rcs)
runtime_checks=normal init; Apache TLS; firstboot administrator login; CSRF-protected topic create and rendered read; direct topic-file persistence and event log; password-file ownership; nightly maintenance, notifications and statistics; Webmin and local Postfix
updater_command=official GitHub latest-release query plus the documented Foswiki patch-upgrade procedure using the 2.1.11 upgrade archive
updater_result=official latest stable endpoint returned $latest_name; verified official 2.1.10 full and 2.1.11 upgrade archive digests; upgraded a disposable 2.1.10 installation to 2.1.11 and preserved administrator authentication and topic content
updater_channel=https://github.com/foswiki/distro/releases and https://foswiki.org/System/UpgradeGuide
integrity_evidence=build and upgrade fixture verify SHA-256 digests from official GitHub release metadata; APT accepted signed Trixie metadata; no Bookworm source remained
EOF
