use strict;
use warnings;
use Test::More 0.96;
use utf8;

use Test::DZil;
use Test::Fatal;
use Version::Next qw/next_version/;

sub _new_tzil {
    my $c = shift;
    my @plugins =
      $c->{global}
      ? (
        [ GatherDir      => { exclude_filename => ['Makefile.PL'] } ],
        [ RewriteVersion => { global           => 1 } ],
        'FakeRelease',
        [ BumpVersionAfterRelease => { global => 1 } ],
        'MakeMaker'
      )
      : (
        [ GatherDir => { exclude_filename => ['Makefile.PL'] } ],
        qw(RewriteVersion FakeRelease BumpVersionAfterRelease MakeMaker)
      );

    return Builder->from_config(
        { dist_root => 'corpus/DZT' },
        {
            add_files => { 'source/dist.ini' => simple_ini( { version => undef }, @plugins ), },
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
        version  => "0.005",
        override => 1,
    },
    {
        label   => "identity trial version",
        version => "0.001",
        trial   => 1,
    },
    {
        label    => "rewrite trial version",
        version  => "0.005",
        override => 1,
        trial    => 1,
    },
    {
        label    => "global replacement",
        version  => "0.005",
        override => 1,
        trial    => 1,
        global   => 1,
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
        my $tzil = _new_tzil($c);
        $tzil->chrome->logger->set_debug(1);

        $tzil->build;

        pass("dzil build");

        my $sample_src = $tzil->slurp_file('source/lib/DZT/Sample.pm');
        my $sample_bld = $tzil->slurp_file('build/lib/DZT/Sample.pm');
        my $sample_re  = _regex_for_version( q['], $version, $c->{trial} ? "# TRIAL" : "" );
        my $dquote_bld = $tzil->slurp_file('build/lib/DZT/DQuote.pm');

        like(
            $sample_src,
            _regex_for_version( q['], '0.001', "# comment" ),
            "single-quoted version line correct in source file",
        );

        like( $sample_bld, $sample_re, "single-quoted version line correct in built file" );

        my $count =()= $sample_bld =~ /$sample_re/mg;
        my $exp = $c->{global} || ( !$c->{trial} && $label =~ /identity/ ) ? 2 : 1;
        is( $count, $exp, "right number of replacements" )
          or diag $sample_bld;

        like(
            $tzil->slurp_file('source/lib/DZT/DQuote.pm'),
            _regex_for_version( q["], '0.001', "# comment" ),
            "double-quoted version line correct in source file",
        );

        like(
            $dquote_bld,
            _regex_for_version( q['], $version, $c->{trial} ? "# TRIAL" : "" ),
            "double-quoted version line changed to single in build file"
        );

        like( $dquote_bld, qr/1;\s+# last line/, "last line correct in double-quoted file" );

        ok(
            grep( { /adding \$VERSION assignment/ } @{ $tzil->log_messages } ),
            "we log adding a version",
        ) or diag join( "\n", @{ $tzil->log_messages } );

        my $makefilePL = $tzil->slurp_file('build/Makefile.PL');

        like( $makefilePL, _regex_for_makefilePL($version), "Makefile.PL version bumped" );

        # after release

        $tzil->release;

        pass("dzil release");

        ok(
            grep( { /fake release happen/i } @{ $tzil->log_messages } ),
            "we log a fake release when we fake release",
        );

        my $orig = $tzil->slurp_file('source/lib/DZT/Sample.pm');
        my $next_re = _regex_for_version( q['], next_version($version) );

        like( $orig, $next_re, "version line updated in single-quoted source file" );

        $count =()= $orig =~ /$next_re/mg;
        $exp = $c->{global} ? 2 : 1;
        is( $count, $exp, "right number of replacements" )
          or diag $orig;

        like( $orig, qr/1;\s+# last line/,
            "last line correct in single-quoted source file" );

        $orig = $tzil->slurp_file('source/lib/DZT/DQuote.pm');

        like(
            $orig,
            _regex_for_version( q['], next_version($version) ),
            "version line updated from double-quotes to single-quotes in source file",
        );

        like( $orig, qr/1;\s+# last line/, "last line correct in revised source file" );

        $makefilePL = $tzil->slurp_file('source/Makefile.PL');

        like(
            $makefilePL,
            _regex_for_makefilePL( next_version($version) ),
            "Makefile.PL version bumped"
        );

    };
}

done_testing;
