
use strict;

sub POE::Kernel::ASSERT_ALL () { 1 }

use POE;

use lib qw(../blib/arch ../blib/lib);
use POE::Component::RRDTool;

use Test::More tests => 1;

my $RRD_VERSION = $POE::Component::RRDTool::RRDTOOL_VERSION;

SKIP: {
    skip "rrdtool v${RRD_VERSION} does not support xport", 1 
        unless &supports_xport( $RRD_VERSION );

    #----------------------#
    #  Test 7: RRD xport   #
    #----------------------#

    my $ok = 0;

    my @xport_args = (
      '--start', -300,
      '--step', 300, 
      'DEF:x=test.rrd:X:MAX',
      'XPORT:x:foobar',
    );

    my $alias = 'controller';
    POE::Component::RRDTool->new(
        -alias   => $alias,
    );

    POE::Session->create(
        inline_states => {
            _start => sub { 
                $_[KERNEL]->alias_set($_[ARG0]);
                $_[KERNEL]->post( 'rrdtool', 'xport', 'get_value', @xport_args );
                $_[KERNEL]->post( 'rrdtool', 'stop' );
            },
            'get_value' => sub {
                my $xml = $_[ARG0];
                $ok = 1 if $$xml;
            },
            'rrd_error' => sub { 
                $ok = 0; 
                print STDERR "ERROR: " . $_[ARG0] . "\n";  
            },
        },
        args => [ $alias ],
    );

    $poe_kernel->run();

    ok($ok, 'rrd xport returned some data');

};

exit 0;


sub supports_xport {
    my $rrd_version = shift || return;
    my($major, $minor, $subminor) = split(/\./, $rrd_version);
    return 1 if $major > 0 && $minor > -1 && $subminor > 37;
}

