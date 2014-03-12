puppet-opendj
=============

`puppet-opendj` configures your ForgeRock OpenDJ servers for use with OpenAM.

## Usage
In your hieradata file...

Basic usage:
```yaml
---
opendj::admin_password: my_password
opendj::base_dn: dc=example,dc=com
```

With more options:
```yaml
---
opendj::ldap_port: 1389
opendj::ldaps_port: 1636
opendj::admin_port: 4444
opendj::repl_port: 8989
opendj::jmx_port: 1689
opendj::admin_user: cn=My User
opendj::admin_password: my_password
opendj::base_dn: dc=example,dc=com
opendj::home: /opt/opendj
opendj::user: opendj
opendj::group: opendj
opendj::host: opendj.com
opendj::tmpdir: /tmp

# For slave
opendj::master: opendj-master.com

# Overwrite values in ${opendj::home}/config/java.properties
opendj::java_properties:
    start-ds.java-args: -server -Xms2G -Xmx2G -XX:+UseConcMarkSweepGC -XX:NewSize=512M
    import-ldif.offline.java-args: -server -Xms1024M -Xmx1024M
    ...
```