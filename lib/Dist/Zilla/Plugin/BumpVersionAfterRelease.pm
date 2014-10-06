use 5.008001;
use strict;
use warnings;

package Dist::Zilla::Plugin::BumpVersionAfterRelease;
# ABSTRACT: Bump module versions after distribution release

our $VERSION = '0.004';

use Moose;
with(
    'Dist::Zilla::Role::AfterRelease' => { -version => 5 },
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

#pod =attr munge_makefile_pl
#pod
#pod If there is a F<Makefile.PL> in the root of the repository, its version will be
#pod set as well.  Defaults to true.
#pod
#pod =cut

has munge_makefile_pl => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
);

has _next_version => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build__next_version',
);

sub _build__next_version {
    my ($self) = @_;
    require Version::Next;
    my $version = $self->zilla->version;
    $self->log_fatal("$version is not a valid version string")
      unless version::is_lax($version);
    return Version::Next::next_version($version);
}

sub after_release {
    my ($self) = @_;
    $self->munge_file($_) for @{ $self->found_files };
    $self->rewrite_makefile_pl if -f "Makefile.PL" && $self->munge_makefile_pl;
    return;
}

sub munge_file {
    my ( $self, $file ) = @_;

    return if $file->is_bytes;

    if ( $file->name =~ m/\.pod$/ ) {
        $self->log_debug( [ 'Skipping: "%s" is pod only', $file->name ] );
        return;
    }

    if ( !-r $file->name ) {
        $self->log_debug( [ 'Skipping: "%s" not found in source', $file->name ] );
        return;
    }

    if ( $self->rewrite_version( $file, $self->_next_version ) ) {
        $self->log_debug( [ 'bumped $VERSION in %s', $file->name ] );
    }
    else {
        $self->log( [ q[Skipping: no "our $VERSION = '...'" found in "%s"], $file->name ] );
    }
    return;
}

my $assign_regex = qr{
    our \s+ \$VERSION \s* = \s* (['"])$version::LAX\1 \s* ;
}x;

sub rewrite_version {
    my ( $self, $file, $version ) = @_;

    require Path::Tiny;

    my $iolayer = sprintf( ":raw:encoding(%s)", $file->encoding );

    # read source file
    my $content = Path::Tiny::path( $file->name )->slurp( { binmode => $iolayer } );

    my $comment = $self->zilla->is_trial ? ' # TRIAL' : '';
    my $code = "our \$VERSION = '$version';$comment";

    if (
        $self->global
        ? ( $content =~ s{^$assign_regex[^\n]*$}{$code}msg )
        : ( $content =~ s{^$assign_regex[^\n]*$}{$code}ms )
      )
    {
        Path::Tiny::path( $file->name )->spew( { binmode => $iolayer }, $content );
        return 1;
    }

    return;
}

sub rewrite_makefile_pl {
    my ($self) = @_;

    my $next_version = $self->_next_version;

    require Path::Tiny;

    my $path = Path::Tiny::path("Makefile.PL");

    my $content = $path->slurp_utf8;

    if ( $content =~ s{"VERSION" => "[^"]+"}{"VERSION" => "$next_version"}ms ) {
        $path->spew_utf8($content);
        return 1;
    }

    return;
}

1;


# vim: ts=4 sts=4 sw=4 et:

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::BumpVersionAfterRelease - Bump module versions after distribution release

=head1 VERSION

version 0.004

=head1 SYNOPSIS

In your code, declare C<$VERSION> like this:

    package Foo;
    our $VERSION = '1.23';

In your F<dist.ini>:

    [RewriteVersion]

    [BumpVersionAfterRelease]

=head1 DESCRIPTION

After a release, this module modifies your original source code to replace an
existing C<our $VERSION = '1.23'> declaration with the next number after the
released version as determined by L<Version::Next>.  Only the B<first>
occurrence is affected (unless you set the L</global> attribute) and it must
exactly match this regular expression:

    qr{^our \s+ \$VERSION \s* = \s* '$version::LAX'}mx

It must be at the start of a line and any trailing comments are deleted.  The
original may have double-quotes, but the re-written line will have single
quotes.

The very restrictive regular expression format is intentional to avoid
the various ways finding a version assignment could go wrong and to avoid
using L<PPI>, which has similar complexity issues.

For most modules, this should work just fine.

=head1 USAGE

This L<Dist::Zilla> plugin, along with
L<RewriteVersion|Dist::Zilla::Plugin::RewriteVersion> let you leave a
C<$VERSION> declaration in the code files in your repository but still let
Dist::Zilla provide automated version management.

First, you include a very specific C<$VERSION> declaration in your code:

    our $VERSION = '0.001';

It must be on a line by itself and should be the same in all your files.
(If it is not, it will be overwritten anyway.)

L<RewriteVersion|Dist::Zilla::Plugin::RewriteVersion> is a version provider
plugin, so the version line from your main module will be used as the version
for your release.

If you override the version with the C<V> environment variable,
then L<RewriteVersion|Dist::Zilla::Plugin::RewriteVersion> will overwrite the
C<$VERSION> declaration in the gathered files.

    V=1.000 dzil release

Finally, after a successful release, this module
L<BumpVersionAfterRelease|Dist::Zilla::Plugin::BumpVersionAfterRelease> will
overwrite the C<$VERSION> declaration in your B<source> files to be the B<next>
version after the one you just released.  That version will then be the default
one that will be used for the next release.

If you tag/commit after a release, you may want to tag and commit B<before>
the source files are modified.  Here is a sample C<dist.ini> that shows
how you might do that.

    name    = Foo-Bar
    author  = David Golden <dagolden@cpan.org>
    license = Apache_2_0
    copyright_holder = David Golden
    copyright_year   = 2014

    [@Basic]

    [RewriteVersion]

    ; commit source files as of "dzil release" with any
    ; allowable modifications (e.g Changes)
    [Git::Commit / Commit_Dirty_Files] ; commit files/Changes (as released)

    ; tag as of "dzil release"
    [Git::Tag]

    ; update Changes with timestamp of release
    [NextRelease]

    [BumpVersionAfterRelease]

    ; commit source files after modification
    [Git::Commit / Commit_Changes] ; commit Changes (for new dev)
    allow_dirty_match = ^lib/
    commit_msg = Commit Changes and bump $VERSION

=head1 ATTRIBUTES

=head2 global

If true, all occurrences of the version pattern will be replaced.  Otherwise,
only the first occurrence is replaced.  Defaults to false.

=head2 munge_makefile_pl

If there is a F<Makefile.PL> in the root of the repository, its version will be
set as well.  Defaults to true.

=for Pod::Coverage after_release munge_file rewrite_makefile_pl rewrite_version

=head1 SEE ALSO

Here are some other plugins for managing C<$VERSION> in your distribution:

=over 4

=item *

L<Dist::Zilla::Plugin::PkgVersion>

=item *

L<Dist::Zilla::Plugin::OurPkgVersion>

=item *

L<Dist::Zilla::Plugin::OverridePkgVersion>

=item *

L<Dist::Zilla::Plugin::SurgicalPkgVersion>

=item *

L<Dist::Zilla::Plugin::PkgVersionIfModuleWithPod>

=back

=for :stopwords cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto metadata placeholders metacpan

=head1 SUPPORT

=head2 Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at L<https://github.com/dagolden/Dist-Zilla-Plugin-BumpVersionAfterRelease/issues>.
You will be notified automatically of any progress on your issue.

=head2 Source Code

This is open source software.  The code repository is available for
public review and contribution under the terms of the license.

L<https://github.com/dagolden/Dist-Zilla-Plugin-BumpVersionAfterRelease>

  git clone https://github.com/dagolden/Dist-Zilla-Plugin-BumpVersionAfterRelease.git

=head1 AUTHOR

David Golden <dagolden@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2014 by David Golden.

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

=cut
