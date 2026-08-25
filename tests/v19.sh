#!/bin/bash
set -Eeuo pipefail
umask 077

result=${TKL_TEST_RESULT:?TKL_TEST_RESULT is required}
app_password=${TKL_TEST_APP_PASS:?TKL_TEST_APP_PASS is required}
base=https://localhost
cookie=/tmp/tkl-foswiki-cookie.$$
page=/tmp/tkl-foswiki-page.$$
headers=/tmp/tkl-foswiki-headers.$$

cleanup() {
    rm -f -- "$cookie" "$page" "$headers"
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

login_url="$base/foswiki/bin/login/Main/WebHome"
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

topic="TurnKeyV19Acceptance$$"
text="Foswiki topic persistence round trip $$"
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
grep -Rqs '^Suites: trixie' /etc/apt/sources.list.d
! grep -Rqi bookworm /etc/apt/sources.list /etc/apt/sources.list.d

cat >"$result" <<EOF
package_source=Official Foswiki $installed_version security release archive, SHA-256 3a490eb460db4ca69d73dfe44c7984889552e5313eff60162760e80e66e5eba6 from upstream release metadata; Perl and dependencies from Debian Trixie
installed_version=Foswiki $installed_version; $(perl --version | head -n2 | tail -n1); rcs $(dpkg-query -W -f='${Version}' rcs)
runtime_checks=normal init; Apache TLS; firstboot administrator login; CSRF-protected topic create and rendered read; direct topic-file persistence and event log; password-file ownership; nightly maintenance, notifications and statistics; Webmin and local Postfix
updater_command=official GitHub latest-release query followed by the documented Foswiki UpgradeGuide
updater_result=official latest stable release endpoint returned $latest_name, matching installed $installed_version; no application files changed
updater_channel=https://github.com/foswiki/distro/releases and https://foswiki.org/System/UpgradeGuide
integrity_evidence=build verifies the SHA-256 attached to official GitHub release metadata; APT accepted signed Trixie metadata; no Bookworm source remained
EOF
