use strict;
use warnings;
use Test::More 0.96;
use utf8;

use Test::DZil;
use Test::Fatal;
use Version::Next qw/next_version/;

sub _new_tzil {
    return Builder->from_config(
        { dist_root => 'corpus/DZT' },
        {
            add_files => {
                'source/dist.ini' => simple_ini(
                    { version => undef },
                    qw(GatherDir RewriteVersion FakeRelease BumpVersionAfterRelease)
                ),
            },
        },
    );
}

my @cases = (
    {
        label   => "identity rewrite",
        version => "0.001",
    },
    {
        label    => "simple rewrite",
        version  => "0.002",
        override => 1,
    },
    {
        label   => "identity trial version",
        version => "0.001",
        trial   => 1,
    },
    {
        label    => "rewrite trial version",
        version  => "0.002",
        override => 1,
        trial    => 1,
    },
);

sub _regex_for_version {
    my ( $q, $version, $trailing ) = @_;
    my $exp = $trailing
      ? qr{^our \$VERSION = $q\Q$version\E$q; \Q$trailing\E}m
      : qr{^our \$VERSION = $q\Q$version\E$q;}m;
    return $exp;
}

sub _regex_for_makefilePL {
    my ($version) = @_;
    return qr{"VERSION" => "\Q$version\E"}m;
}

for my $c (@cases) {
    my ( $label, $version ) = @{$c}{qw/label version/};
    subtest $label => sub {
        local $ENV{TRIAL} = $c->{trial};
        local $ENV{V} = $version if $c->{override};
        my $tzil = _new_tzil;
        $tzil->chrome->logger->set_debug(1);

        $tzil->build;

        pass("dzil build");

        like(
            $tzil->slurp_file('source/lib/DZT/Sample.pm'),
            _regex_for_version( q['], '0.001', "# comment" ),
            "single-quoted version line correct in source file",
        );

        like(
            $tzil->slurp_file('source/lib/DZT/DQuote.pm'),
            _regex_for_version( q["], '0.001', "# comment" ),
            "double-quoted version line correct in source file",
        );

        my $built = $tzil->slurp_file('build/lib/DZT/Sample.pm');

        like(
            $built,
            _regex_for_version( q['], $version, $c->{trial} ? "# TRIAL" : "" ),
            "single-quoted version line correct in built file",
        );

        like( $built, qr/1;\s+# last line/, "last line correct in single-quoted file" );

        $built = $tzil->slurp_file('build/lib/DZT/DQuote.pm');

        like(
            $built,
            _regex_for_version( q['], $version, $c->{trial} ? "# TRIAL" : "" ),
            "double-quoted version line changed to single in built file"
        );

        like( $built, qr/1;\s+# last line/, "last line correct in single-quoted file" );

        ok(
            grep( { /adding \$VERSION assignment/ } @{ $tzil->log_messages } ),
            "we log adding a version",
        ) or diag join( "\n", @{ $tzil->log_messages } );

        $tzil->release;

        pass("dzil release");

        ok(
            grep( { /fake release happen/i } @{ $tzil->log_messages } ),
            "we log a fake release when we fake release",
        );

        my $orig = $tzil->slurp_file('source/lib/DZT/Sample.pm');

        like(
            $orig,
            _regex_for_version( q['], next_version($version) ),
            "version line updated in single-quoted source file",
        );

        like( $orig, qr/1;\s+# last line/,
            "last line correct in single-quoted source file" );

        $orig = $tzil->slurp_file('source/lib/DZT/DQuote.pm');

        like(
            $orig,
            _regex_for_version( q['], next_version($version) ),
            "version line updated from double-quotes to single-quotes in source file",
        );

        like( $orig, qr/1;\s+# last line/, "last line correct in revised source file" );

        my $makefilePL = $tzil->slurp_file('source/Makefile.PL');

        like(
            $makefilePL,
            _regex_for_makefilePL( next_version($version) ),
            "Makefile.PL version bumped"
        );

    };
}

done_testing;
