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
package Yummo::Store;

use warnings;
use strict;

use Data::Dumper;

use Yummo::Store::Repository;

sub new {
  my $class = shift;
  my $repos = shift // [];

  # validate path
  die 'Unable to read repos' unless ref( $repos ) eq 'ARRAY';

  my $self = {
    _repos => {},
  };

  bless $self, $class;

  foreach my $r ( @$repos ) {
    $self->add_respository( $r );
  }

  return $self;
}

sub _filter_repos {
  my $self = shift;
  my %params = @_;

  my @list = keys $self->{_repos};

  # check for explicit repo identifier
  if( defined( $params{repoid} ) ) {
    @list = grep { $self->{_repos}{$_}->id eq $params{repoid} } @list;
  }

  # otherwise we're searching
  if( defined( $params{repo} ) ) {
    @list = grep { index($self->{_repos}{$_}->name, $params{repo}) > -1 } @list;
  }

  if( defined( $params{arch} ) ) {
    @list = grep { $self->{_repos}{$_}->arch eq $params{arch} } @list;
  }

  if( defined( $params{release} ) ) {
    @list = grep { $self->{_repos}{$_}->release eq $params{release} } @list;
  }

  return \@list;
}

sub add_repository {
  my $self = shift;
  my %params = @_;

  my $r = Yummo::Store::Repository->new( %params );

  if( defined( $self->{_repos}{ $r->id } ) ) {
    if( $r->checksum eq $self->{_repos}{ $r->id } ) {
      return;
    }

    # TODO: clean up old repo and clear cache
  }

  # add new repo
  $self->{_repos}{ $r->id } = $r;
}

sub load_repository_directory {
  my $self = shift;
  my %params = @_;
  my $path = "./repos";

  my @archs = ();
  my @releases = ();

  # find archs
  opendir(DIR, $path) or die 'Unable to open directory.';
  my @paths = grep { !/^\.{1,2}$/ } readdir (DIR);
  close(DIR);

  @archs = grep { -d "$path/$_" } @paths;

  # find releases
  foreach my $a ( @archs ) {
    opendir(DIR, "$path/$a") or die 'Unable to open directory.';
    my @paths = grep { !/^\.{1,2}$/ } readdir (DIR);
    close(DIR);

    foreach my $r ( @paths ) {
      push @releases, $r if( -d "$path/$a/$r" );
    }
  }

  return unless( @archs > 0 && @releases > 0 );

  # process all repo db's
  foreach my $a ( @archs ) {
    foreach my $r ( @releases ) {
      opendir(DIR, "$path/$a/$r") or die 'Unable to open directory.';
      my @paths = grep { /\.sqlite/ } readdir (DIR);
      close(DIR);

      foreach my $p ( @paths ) {
        my($checksum, $name, $suffix) = split /\./, $p;

        $self->add_repository(
          name      => $name,
          release   => $r,
          arch      => $a,
          checksum  => $checksum,
          path      => "$path/$a/$r/$p"
        );
      }
    }
  }
}

sub repositories {
  my $self = shift;
  my %params = @_;

  return $self->_filter_repos( %params );
}

sub packages_count {
  my $self = shift;
  my %params = @_;
  my $packages_count = 0;

  foreach my $r ( @{ $self->_filter_repos( %params ) } ) {
    $packages_count += $self->{_repos}{ $r }->packages_count( %params );
  }

  return $packages_count;
}

sub packages {
  my $self = shift;
  my %params = @_;
  my $packages = {};

  foreach my $r ( @{ $self->_filter_repos( %params ) } ) {
    my $p = $self->{_repos}{ $r }->packages( %params );

    # merge results from all repositories
    foreach my $n ( keys $p ) {
      $packages->{$n} //= [];
      push @{ $packages->{$n} }, @{ $p->{$n} };
    }
  }

  return $packages;
}

sub package_details {
  my $self = shift;
  my %params = @_;
  my $packages = {};

  foreach my $r ( @{ $self->_filter_repos( %params ) } ) {
    my $p = $self->{_repos}{ $r }->package_details( %params );
    # merge results from all repositories
    foreach my $n ( keys $p ) {
      $packages->{$n} //= [];
      push @{ $packages->{$n} }, @{ $p->{$n} };
    }
  }

  return $packages;
}

sub package_conflicts {
  my $self = shift;
  my %params = @_;
  my $conflicts = [];

  foreach my $r ( @{ $self->_filter_repos( %params ) } ) {
    $conflicts = $self->{_repos}{ $r }->package_conflicts( %params );
  }

  return $conflicts;
}


sub package_obsoletes {
  my $self = shift;
  my %params = @_;
  my $obsoletes = [];

  foreach my $r ( @{ $self->_filter_repos( %params ) } ) {
    $obsoletes = $self->{_repos}{ $r }->package_obsoletes( %params );
  }

  return $obsoletes;
}



sub package_provnamees {
  my $self = shift;
  my %params = @_;
  my $provides = [];

  foreach my $r ( @{ $self->_filter_repos( %params ) } ) {
    $provides = $self->{_repos}{ $r }->package_provides( %params );
  }


  return $provides;
}

sub package_requires {
  my $self = shift;
  my %params = @_;
  my $requires = [];

  foreach my $r ( @{ $self->_filter_repos( %params ) } ) {
    $requires = $self->{_repos}{ $r }->package_requires( %params );
  }

  return $requires;
}

1;
