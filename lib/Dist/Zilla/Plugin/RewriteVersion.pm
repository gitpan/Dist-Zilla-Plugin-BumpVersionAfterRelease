use 5.008001;
use strict;
use warnings;

package Dist::Zilla::Plugin::RewriteVersion;
# ABSTRACT: Get and/or rewrite module versions to match distribution version

our $VERSION = '0.006';

use Moose;
with(
    'Dist::Zilla::Role::FileMunger' => { -version => 5 },
    'Dist::Zilla::Role::VersionProvider',
    'Dist::Zilla::Role::FileFinderUser' =>
      { default_finders => [ ':InstallModules', ':ExecFiles' ], },
);

use namespace::autoclean;
use version ();

#pod =attr global
#pod
#pod If true, all occurrences of the version pattern will be replaced.  Otherwise,
#pod only the first occurrence is replaced.  Defaults to false.
#pod
#pod =cut

has global => (
    is  => 'ro',
    isa => 'Bool',
);

my $assign_regex = qr{
    our \s+ \$VERSION \s* = \s* (['"])($version::LAX)\1 \s* ;
}x;

#pod =attr skip_version_provider
#pod
#pod If true, rely on some other mechanism for determining the "current" version
#pod instead of extracting it from the C<main_module>. Defaults to false.
#pod
#pod This enables hard-coding C<version => in C<dist.ini> among other tricks.
#pod
#pod =cut

has skip_version_provider => ( is => ro =>, lazy => 1, default => undef );

sub provide_version {
    my ($self) = @_;
    return if $self->skip_version_provider;
    # override (or maybe needed to initialize)
    return $ENV{V} if exists $ENV{V};

    my $file    = $self->zilla->main_module;
    my $content = $file->content;

    my ( $quote, $version ) = $content =~ m{^$assign_regex[^\n]*$}ms;

    return $version;
}

sub munge_files {
    my $self = shift;
    $self->munge_file($_) for @{ $self->found_files };
    return;
}

sub munge_file {
    my ( $self, $file ) = @_;

    return if $file->is_bytes;

    if ( $file->name =~ m/\.pod$/ ) {
        $self->log_debug( [ 'Skipping: "%s" is pod only', $file->name ] );
        return;
    }

    my $version = $self->zilla->version;

    $self->log_fatal("$version is not a valid version string")
      unless version::is_lax($version);

    if ( $self->rewrite_version( $file, $version ) ) {
        $self->log_debug( [ 'adding $VERSION assignment to %s', $file->name ] );
    }
    else {
        $self->log( [ q[Skipping: no "our $VERSION = '...'" found in "%s"], $file->name ] );
    }
    return;
}

sub rewrite_version {
    my ( $self, $file, $version ) = @_;

    my $content = $file->content;

    my $comment = $self->zilla->is_trial ? ' # TRIAL' : '';
    my $code = "our \$VERSION = '$version';$comment";

    if (
        $self->global
        ? ( $content =~ s{^$assign_regex[^\n]*$}{$code}msg )
        : ( $content =~ s{^$assign_regex[^\n]*$}{$code}ms )
      )
    {
        $file->content($content);
        return 1;
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;


# vim: ts=4 sts=4 sw=4 et:

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::RewriteVersion - Get and/or rewrite module versions to match distribution version

=head1 VERSION

version 0.006

=head1 SYNOPSIS

    # in your code, declare $VERSION like this:
    package Foo;
    our $VERSION = '1.23';

    # in your dist.ini
    [RewriteVersion]

=head1 DESCRIPTION

This module is both a C<VersionProvider> and C<FileMunger>.

This module finds a version in a specific format from the main module file and
munges all gathered files to match.  You can override the version found with
the C<V> environment variable, similar to
L<Git::NextVersion|Dist::Zilla::Plugin::Git::NextVersion>, in which case all
the gathered files have their C<$VERSION> set to that value.

Only the B<first> occurrence of a C<$VERSION> declaration in each file is
relevant and/or affected (unless the L</global> attribute is set and it must
exactly match this regular expression:

    qr{^our \s+ \$VERSION \s* = \s* '$version::LAX'}mx

It must be at the start of a line and any trailing comments are deleted.  The
original may have double-quotes, but the re-written line will have single
quotes.

The very restrictive regular expression format is intentional to avoid
the various ways finding a version assignment could go wrong and to avoid
using L<PPI>, which has similar complexity issues.

For most modules, this should work just fine.

See L<BumpVersionAfterRelease|Dist::Zilla::Plugin::BumpVersionAfterRelease> for
more details and usage examples.

=head1 ATTRIBUTES

=head2 global

If true, all occurrences of the version pattern will be replaced.  Otherwise,
only the first occurrence is replaced.  Defaults to false.

=head2 skip_version_provider

If true, rely on some other mechanism for determining the "current" version
instead of extracting it from the C<main_module>. Defaults to false.

This enables hard-coding C<version => in C<dist.ini> among other tricks.

=for Pod::Coverage munge_files munge_file rewrite_version provide_version

=head1 AUTHOR

David Golden <dagolden@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2014 by David Golden.

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

=cut
