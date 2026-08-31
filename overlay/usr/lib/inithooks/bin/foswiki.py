#!/usr/bin/python3
"""Set FosWiki admin password and email

Option:
    --pass=     unless provided, will ask interactively
    --email=    unless provided, will ask interactively
    --domain=   unless provided, will ask interactively
                DEFAULT www.example.com
"""

import sys
import getopt
from subprocess import check_output, run

from libinithooks import inithooks_cache
from libinithooks.dialog_wrapper import Dialog


def usage(s=None):
    if s:
        print("Error:", s, file=sys.stderr)
    print("Syntax: %s [options]" % sys.argv[0], file=sys.stderr)
    print(__doc__, file=sys.stderr)
    sys.exit(1)


DEFAULT_DOMAIN = 'www.example.com'


def main():
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], "h",
                                       ['help', 'pass=', 'email=', 'domain='])
    except getopt.GetoptError as e:
        usage(e)

    password = ""
    email = ""
    domain = ""
    for opt, val in opts:
        if opt in ('-h', '--help'):
            usage()
        elif opt == '--pass':
            password = val
        elif opt == '--email':
            email = val
        elif opt == '--domain':
            domain = val

    if not password:
        d = Dialog('TurnKey Linux - First boot configuration')
        password = d.get_password(
            "Foswiki Password",
            "Enter new password for the Foswiki 'admin' account.")

    if not email:
        if 'd' not in locals():
            d = Dialog('TurnKey Linux - First boot configuration')

        email = d.get_email(
            "Foswiki Email",
            "Enter email address for the Foswiki 'admin' account.",
            "admin@example.com")

    inithooks_cache.write('APP_EMAIL', email)

    if not domain:
        if 'd' not in locals():
            d = Dialog('Turnkey Linux - First boot configuration')

        domain = d.get_input(
            "Foswiki Domain",
            "Enter the domain to serve Foswiki.",
            DEFAULT_DOMAIN)

    if domain == "DEFAULT":
        domain = DEFAULT_DOMAIN

    inithooks_cache.write('APP_DOMAIN', domain)

    if not (domain.startswith('http://') or domain.startswith('https://')):
        domain = 'https://' + domain

    check_output(['perl', '-CA', '/var/www/foswiki/tools/configure', '-save',
                  '-set', '{Password}=%s' % password,
                  '-set', '{WebMasterEmail}=%s' % email,
                  '-set', '{DefaultUrlHost}=%s' % domain])
    run(['htpasswd', '-ci', '/var/www/foswiki/data/.htpasswd', 'admin'],
        input=password + '\n', text=True, check=True)


if __name__ == "__main__":
    main()
