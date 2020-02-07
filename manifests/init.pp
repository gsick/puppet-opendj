# == Class: opendj
#
# Module for deployment and configuration of ForgeRock OpenDJ.
#
# === Authors
#
# Eivind Mikkelsen <eivindm@conduct.no>
#
# === Copyright
#
# Copyright (c) 2013 Conduct AS
#

class opendj (
  $ldap_port       = hiera('opendj::ldap_port', '1389'),
  $ldaps_port      = hiera('opendj::ldaps_port', '1636'),
  $admin_port      = hiera('opendj::admin_port', '4444'),
  $repl_port       = hiera('opendj::repl_port', '8989'),
  $jmx_port        = hiera('opendj::jmx_port', '1689'),
  $admin_user      = hiera('opendj::admin_user', 'cn=Directory Manager'),
  $admin_password  = hiera('opendj::admin_password'),
  $base_dn         = hiera('opendj::base_dn'),
  $home            = hiera('opendj::home', '/opt/opendj'),
  $user            = hiera('opendj::user', 'opendj'),
  $group           = hiera('opendj::group', 'opendj'),
  $host            = hiera('opendj::host', $fqdn),
  $tmp             = hiera('opendj::tmpdir', '/tmp'),
  $master          = hiera('opendj::master', undef),
  $java_properties = hiera('opendj::java_properties', undef),
) {
  $common_opts   = "-h ${host} -D '${opendj::admin_user}' -w ${opendj::admin_password}"
  $ldapsearch    = "${opendj::home}/bin/ldapsearch ${common_opts} -p ${opendj::ldap_port}"
  $ldapmodify    = "${opendj::home}/bin/ldapmodify ${common_opts} -p ${opendj::ldap_port}"
  $dsconfig      = "${opendj::home}/bin/dsconfig   ${common_opts} -p ${opendj::admin_port} -X -n"
  $dsreplication = "${opendj::home}/bin/dsreplication --adminUID admin --adminPassword ${admin_password} -X -n"

  require java

  package { "opendj":
    ensure => present,
  }

  group { "${group}":
    ensure => "present",
  }

  user { "${user}":
    ensure => "present",
    groups => $group,
    managehome => true,
    require => Group["${group}"],
  }

  file { "${home}":
    ensure => directory,
    owner => $user,
    group => $group,
    recurse => true,
    require => [User["${user}"], Package["opendj"]],
  }

  file { "${tmp}/opendj.properties":
    ensure => file,
    content => template("${module_name}/setup.erb"),
    owner  => $user,
    group  => $group,
    mode => 0600,
    require => File["${home}"],
  }

  file_line { 'file_limits_soft':
    path => '/etc/security/limits.conf',
    line => '${user} soft nofile 65536',
    require => User["${user}"],
  }

  file_line { 'file_limits_hard':
    path => '/etc/security/limits.conf',
    line => '${user} hard nofile 131072',
    require => User["${user}"],
  }

  exec { "configure opendj":
    require => File["${tmp}/opendj.properties"],
    command => "/bin/su opendj -s /bin/bash -c '${home}/setup -i \
        -n -Q --acceptLicense --doNotStart --propertiesFilePath ${tmp}/opendj.properties'",
    creates => "${home}/config",
    notify => Exec['create RC script'],
  }

  exec { "create RC script":
    require => Package["opendj"],
    command => "${home}/bin/create-rc-script --userName ${user} \
        --outputFile /etc/init.d/opendj",
    creates => "/etc/init.d/opendj",
    notify => Service['opendj'],
  }

  service { 'opendj':
    require => Exec["create RC script"],
    enable => true,
    ensure => running,
    hasrestart => true,
    hasstatus => false,
    status => "${home}/bin/status -D \"${admin_user}\" \
        --bindPassword ${admin_password} | grep --quiet Started",
  }

  exec { "reject unauthenticated requests":
    require => Service['opendj'],
    command => "/bin/su ${user} -s /bin/bash -c \" \
      $dsconfig set-global-configuration-prop --set reject-unauthenticated-requests:true\"",
    unless => "/bin/su ${user} -s /bin/bash -c \" \
      $dsconfig get-global-configuration-prop | grep 'reject-unauthenticated-requests' | grep true\"",
  }

  exec { "set single structural objectclass behavior":
    command => "${dsconfig} --advanced set-global-configuration-prop --set single-structural-objectclass-behavior:accept",
    unless  => "${dsconfig} --advanced get-global-configuration-prop | grep 'single-structural-objectclass-behavior' | grep accept",
    require => Service['opendj'],
  }

  # Only on master, replicated otherwise
  if !($master) {
    file { "${tmp}/base_dn.ldif":
      ensure => file,
      content => template("${module_name}/base_dn.ldif.erb"),
      owner => $user,
      group => $group,
      mode => 0600,
      require => [User["${user}"], Service['opendj']],
      notify => Exec["create base dn"],
    }

    exec { "create base dn":
      command => "${home}/bin/ldapmodify -a -D '${admin_user}' \
          -w '${admin_password}' -h ${host} -p ${ldap_port} -f '${tmp}/base_dn.ldif'",
      refreshonly => true,
      require => Service['opendj'],
    }
  }

  if ($master != '' and $host != $master) {
   exec { "enable replication":
      require => Service['opendj'],
      command => "/bin/su ${user} -s /bin/bash -c \"$dsreplication enable \
        --host1 ${master} --port1 ${admin_port} \
        --replicationPort1 ${repl_port} \
        --bindDN1 '${admin_user}' --bindPassword1 ${admin_password} \
        --host2 ${host} --port2 ${admin_port} \
        --replicationPort2 ${repl_port} \
        --bindDN2 '${admin_user}' --bindPassword2 ${admin_password} \
        --baseDN '${base_dn}'\"",
      unless => "/bin/su ${user} -s /bin/bash -c \"$dsreplication \
        status | grep ${host} | cut -d : -f 5 | grep true\"",
      notify => Exec["initialize replication"]
    }

    exec { "initialize replication":
      command => "/bin/su ${user} -s /bin/bash -c \"$dsreplication initialize \
        -h ${master} -p ${admin_port} -O ${host} --baseDN '${base_dn}'\"",
      require => Exec["enable replication"],
      refreshonly => true,
    }
  }

  if !empty($java_properties) {
    validate_hash($java_properties)

    create_resources('opendj::java_property', $java_properties)

    exec { "apply java properties":
      command => "/bin/su ${user} -s /bin/bash -c \"${home}/bin/dsjavaproperties\"",
      notify => Service['opendj'],
    }
  }
}
