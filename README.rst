Foswiki - Enterprise Wiki Platform
==================================

`Foswiki`_ is a structured wiki, typically used to run a collaboration
platform, knowledge or document management system, a knowledge base, or
team portal. Users can create wiki applications using the Foswiki Markup
Language, and developers can extend its functionality with plugins.

This appliance includes all the standard features in `TurnKey Core`_,
and on top of that:

- Foswiki configurations:
   
   - Foswiki 2.1.11 is installed from the official release archive to
     /var/www/foswiki. The archive SHA-256 published in the upstream release
     metadata is verified during the build.
   - Configured nightly maintenance, notifications and statistics jobs.
   - Preconfigured mail settings.

     **Security note**: Updates to Foswiki may require supervision so
     they **ARE NOT** configured to install automatically. See `Foswiki
     documentation`_ for upgrading.

     We also recommend subscribing to the `'foswiki-announce' mailing
     list`_ to receive secruity announements in your inbox.

- SSL support out of the box.
- Postfix MTA (bound to localhost) to allow sending of email (e.g.,
  password recovery).
- Webmin modules for configuring Apache2 and Postfix.

WebMasterEmail is configured in */var/www/foswiki/lib/LocalSite.cfg*

Credentials *(passwords set at first boot)*
-------------------------------------------

-  Webmin, SSH: username **root**
-  Foswiki: username **admin**

.. _Foswiki: https://foswiki.org
.. _TurnKey Core: https://www.turnkeylinux.org/core
.. _Foswiki documentation: https://foswiki.org/System/UpgradeGuide
.. _'foswiki-announce' mailing list: https://foswiki.org/Community/MailingLists
