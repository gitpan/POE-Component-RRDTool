use strict;

sub POE::Kernel::ASSERT_ALL () { 1 }

use POE;

use lib qw(../blib/arch ../blib/lib);
use POE::Component::RRDTool;

use Test::More tests => 2;

#-------------------------#
#  Test 2: RRD creation   #
#-------------------------#

my @create_args = qw(
    test.rrd
    --start now
    --step 30
    DS:X:GAUGE:60:0:10
    RRA:MAX:0.5:1:1
);

my $alias = 'controller';
POE::Component::RRDTool->new(
    -alias       => $alias,
    -statusevent => 'rrd_status',
);

my $status_handled = 0;

POE::Session->create(
    inline_states => {
        '_start' => sub { 
             $_[KERNEL]->alias_set($_[ARG0]);
             $_[KERNEL]->post( 'rrdtool', 'create', @create_args );
             $_[KERNEL]->post( 'rrdtool', 'stop' );
        },
        'rrd_error' => sub {
            print STDERR "ERROR: " . $_[ARG0] . "\n";
        },
        'rrd_status'=> sub {
            $status_handled = 1;
        },
    },
    args => [ $alias ],
);

$poe_kernel->run();

my $created = -e "./test.rrd";
ok($created, 'test.rrd was created');

ok($status_handled, 'status event was handled');

exit 0;
