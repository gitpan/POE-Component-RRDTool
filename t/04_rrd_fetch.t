
use strict;

sub POE::Kernel::ASSERT_ALL () { 1 }

use POE;

use lib qw(../blib/arch ../blib/lib);
use POE::Component::RRDTool;

use Test::More tests => 1;

#----------------------#
#  Test 4: RRD fetch   #
#----------------------#

my $ok = 0;

my @fetch_args = qw( test.rrd MAX --start -1s );

my $alias = 'controller';
POE::Component::RRDTool->new(
    -alias   => $alias,
);

POE::Session->create(
    inline_states => {
        _start => sub { 
            $_[KERNEL]->alias_set($_[ARG0]);
            $_[KERNEL]->post( 'rrdtool', 'fetch', 'get_value', @fetch_args );
            $_[KERNEL]->post( 'rrdtool', 'stop' );
        },
        'get_value' => sub {
            my $output = $_[ARG0];
            $ok = 1;
        },
        'rrd_error' => sub { 
            $ok = 0; 
            print STDERR "ERROR: " . $_[ARG0] . "\n";  
        },
    },
    args => [ $alias ],
);

$poe_kernel->run();

ok($ok, 'rrd fetch returned some data');

exit 0;

