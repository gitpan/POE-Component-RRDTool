# -*- perl -*-

use Test::More;
use File::Find;
use Config;
use Cwd		qw/abs_path/;
use Socket;
use Sys::Hostname;

$VERBOSE    = 0;
$TEST_NET   = '207.173.0';

#------------------------------------------------------------
# Main
#------------------------------------------------------------

my $host	= hostname();
my $addr	= inet_ntoa(scalar gethostbyname($host || 'localhost'));
my $cwd		= abs_path();
my $blib	= $cwd =~ /t$/ ? "$cwd/../blib" : "$cwd/blib";
my %pod_files	= ();
my $podchecker	= "$Config{prefix}/bin/podchecker";

if ($addr =~ /^$TEST_NET/) {
    die "Can't find podchecker" unless -e $podchecker;
}

find({ wanted => \&pod_files, follow => 1 }, $blib);
my $num_tests = ((scalar keys %pod_files) * 2);
plan tests => $num_tests;

SKIP: {
    skip "POD testing on non-dev machines", $num_tests
	if $addr !~ /^$TEST_NET/;

    for my $fullpath (sort keys %pod_files) {
	my $file = $pod_files{$fullpath};
	my $out = `$podchecker $fullpath 2>&1`;

	is $?, 0, 				"No system errors checking $file";
	unlike $out, '/(?si:WARNING|ERROR)/',	"POD syntax check of $file"
	    or diag $out;
    }
}

exit;

#------------------------------------------------------------
# Subs
#------------------------------------------------------------

sub pod_files {
    printf STDERR "%-24s", "$_..." if $VERBOSE;
    return unless -f $File::Find::name;

    open F, "< $File::Find::name" or die "Can't open $_: $!";
    $pod_files{$File::Find::name} = $_ if grep /^=head/, <F>;
    close F or warn $!;
}
