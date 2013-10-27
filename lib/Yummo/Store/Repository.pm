#
# Copyright (C) 2013    Ian Firns   <firnsy@kororaproject.org>
#                       Chris Smart <csmart@kororaproject.org>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
package Yummo::Store::Repository;

use warnings;
use strict;

#
# PERL INCLUDES
#
use Data::Dumper;
use DBI;

#
# CONSTANTS
#
use constant PACKAGE_FIELDS_ALL => qw(pkgKey pkgId arch version epoch release summary description url time_file time_build rpm_license rpm_vendor rpm_group rpm_buildhost rpm_sourcerpm rpm_header_start rpm_header_end rpm_packager size_package size_installed size_archive location_href location_base checksum_type);
use constant PACKAGE_FIELDS_MIN => qw(pkgKey pkgId arch version epoch release);

#
# CONSTRUCTOR
#
sub new {
  my $class = shift;
  my %params = @_;

  # validate
  die 'No arch specified' unless defined $params{arch};
  die 'No release specified' unless defined $params{release};
  die 'No name specified' unless defined $params{name};

  die 'Unable to read repository.' unless( defined $params{path} && -r $params{path} );

  my $self = {
    _arch     => $params{arch},
    _release  => $params{release},
    _checksum => $params{checksum},
    _name     => $params{name},
    _id       => '',
    _path     => $params{path},
  };

  bless $self, $class;

  $self->connect;

  return $self;
}

sub connect {
  my $self = shift;

  $self->{_h} = DBI->connect( 'dbi:SQLite:dbname=' . $self->{_path}, '', '' );

  die 'Unable to open database file.' unless $self->{_h};
}

sub id {
  my $self = shift;
  return join('-', $self->{_name}, $self->{_release}, $self->{_arch});
}

sub name {
  my $self = shift;
  return $self->{_name};
}

sub arch {
  my $self = shift;
  return $self->{_arch};
}

sub release {
  my $self = shift;
  return $self->{_release};
}

sub checksum {
  my $self = shift;
  return $self->{_checksum};
}

sub _build_filter {
  my $self = shift;
  my %params = @_;

  my @filter;

  # archs
  if( defined( $params{arch} ) && grep { $_ eq $params{arch} } qw(x86_64 i386 i686 noarch) ) {
    push @filter, "(p.arch='" . $params{arch} . "' OR p.arch='noarch')";
  }

  # name
  if( defined( $params{name} ) ) {
    push @filter, "(p.name='" . $params{name} . "')";
  }

  # create joined filter
  my $filter = join('AND', @filter);
  $filter = " WHERE " . $filter if length( $filter );

  return $filter;
}

sub _build_fields {
  my $self = shift;
  my %params = @_;

  # attempt to break out fields
  my @fields = split ',', $params{fields};

  # validate and de-dupe split fields
  if( @fields ) {
    my %f = map { $_ => 1 } @fields;

    # unique intersection thanks to hash
    @fields = grep( $f{$_}, PACKAGE_FIELDS_ALL );
  }
  else {
    # set default fields to valid minimal
    @fields = PACKAGE_FIELDS_MIN;
  }

  return \@fields;
}

sub packages_count {
  my $self = shift;
  my $filter = $self->_build_filter( @_ );
  my $packages_count = 0;

  if( $self->{_h} ) {
    my $sth = $self->{_h}->prepare('SELECT COUNT(pkgKey) FROM packages AS p' . $filter) or die $self->{_h}->errstr;

    my $rv = $sth->execute;

    if( $rv ) {
      if( my $row = $sth->fetchrow_arrayref ) {
        $packages_count = $row->[0] 
      }
    }

    $sth->finish;
  }

  return $packages_count;
}

sub packages {
  my $self = shift;
  my %params = @_;

  $params{fields} //= "pkgKey,epoch,version,arch,release,time_build,time_file,size_installed,size_package,size_archive";

  my $filter = $self->_build_filter( %params );
  my $fields = [ _uniq('name', @{ $self->_build_fields( %params ) } ) ];

  my $packages = {};

  if( $self->{_h} ) {
    my $sth = $self->{_h}->prepare('SELECT ' . join( ',', map { "p.".$_ } @$fields ) . ' FROM packages AS p' . $filter) or die $self->{_h}->errstr;

    my $rv = $sth->execute;

    if( $rv ) {
      my $row_key;
      my $row_columns = {
        repo => $self->id
      };

      $sth->bind_columns( \$row_key, map { \$row_columns->{$_} } @$fields[1..$#$fields] );

      while( $sth->fetch ) {
        $packages->{$row_key} //= [];
        push $packages->{$row_key}, $row_columns;
      }
    }

    $sth->finish;
  }

  return $packages;
}

sub package_details {
  my $self = shift;
  my %params = @_;

  $params{fields} //= "name,pkgKey,pkgId,arch,version,epoch,release,summary,description,url,time_file,time_build,rpm_license,rpm_vendor,rpm_group,rpm_buildhost,rpm_sourcerpm,rpm_header_start,rpm_header_end,rpm_packager,size_package,size_installed,size_archive,location_href,location_base,checksum_type";

  my $filter = $self->_build_filter( %params );
  my $fields = [ _uniq('name', @{ $self->_build_fields( %params ) } ) ];
  my $packages = {};

  if( $self->{_h} ) {
    my $sth = $self->{_h}->prepare('SELECT ' . join( ',', map { "p.".$_ } @$fields ) .' FROM packages AS p' . $filter) or die $self->{_h}->errstr;

    my $rv = $sth->execute;

    if( $rv ) {
      my $row_key;
      my $row_columns = {
        repo => $self->id
      };

      $sth->bind_columns( \$row_key, map { \$row_columns->{$_} } @$fields[1..$#$fields] );

      while( $sth->fetch ) {
        $packages->{$row_key} //= [];
        push $packages->{$row_key}, $row_columns;
      }
    }

    $sth->finish;
  }

  return $packages;
}

sub package_conflicts {
  my $self = shift;
  my $filter = $self->_build_filter( @_ );
  my $conflicts = [];

  if( $self->{_h} ) {
    my $sth = $self->{_h}->prepare('SELECT c.name, c.epoch, c.version, c.release, c.flags FROM conflicts AS c JOIN packages AS p ON (c.pkgKey=p.pkgKey)' . $filter) or die $self->{_h}->errstr;

    my $rv = $sth->execute;

    if( $rv ) {
      while( my $row = $sth->fetchrow_hashref ) {
        push @$conflicts, $row;
      }
    }

    $sth->finish;
  }

  return $conflicts;
}

sub package_obsoletes {
  my $self = shift;
  my $filter = $self->_build_filter( @_ );
  my $obsoletes = [];

  if( $self->{_h} ) {
    my $sth = $self->{_h}->prepare('SELECT o.name, o.epoch, o.version, o.release, o.flags FROM obsoletes AS o JOIN packages AS p ON (o.pkgKey=p.pkgKey)' . $filter) or die $self->{_h}->errstr;

    my $rv = $sth->execute;

    if( $rv ) {
      while( my $row = $sth->fetchrow_hashref ) {
        push @$obsoletes, $row;
      }
    }

    $sth->finish;
  }

  return $obsoletes;
}

sub package_provides {
  my $self = shift;
  my $filter = $self->_build_filter( @_ );
  my $provides = [];

  if( $self->{_h} ) {
    my $sth = $self->{_h}->prepare('SELECT i.name, i.epoch, i.version, i.release, i.flags FROM provides AS i JOIN packages AS p ON (p.pkgKey=p.pkgKey)' . $filter) or die $self->{_h}->errstr;

    my $rv = $sth->execute;

    if( $rv ) {
      while( my $row = $sth->fetchrow_hashref ) {
        push @$provides, $row;
      }
    }

    $sth->finish;
  }

  return $provides;
}

sub package_requires {
  my $self = shift;
  my $filter = $self->_build_filter( @_ );
  my $requires = [];

  if( $self->{_h} ) {
    my $sth = $self->{_h}->prepare('SELECT r.name, r.epoch, r.version, r.release, r.flags, r.pre FROM requires AS r JOIN packages AS p ON (r.pkgKey=p.pkgKey)' . $filter) or die $self->{_h}->errstr;

    my $rv = $sth->execute;

    if( $rv ) {
      while( my $row = $sth->fetchrow_hashref ) {
        push @$requires, $row;
      }
    }

    $sth->finish;
  }

  return $requires;
}

#
# PRIVATE FUNCTIONS
#
sub _uniq {
  my %seen;
  grep !$seen{$_}++, @_
}

1;
