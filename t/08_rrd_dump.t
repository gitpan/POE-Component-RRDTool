
use strict;

sub POE::Kernel::ASSERT_ALL () { 1 }

use POE;

use lib qw(../blib/arch ../blib/lib);
use POE::Component::RRDTool;

use Test::More tests => 1;

#---------------------#
#  Test 8: RRD dump   #
#---------------------#

my $ok = 0;

my @dump_args = qw( test.rrd );

my $alias = 'controller';
POE::Component::RRDTool->new(
    -alias   => $alias,
);

POE::Session->create(
    inline_states => {
        _start => sub { 
            $_[KERNEL]->alias_set($_[ARG0]);
            $_[KERNEL]->post( 'rrdtool', 'dump', 'get_value', @dump_args );
            $_[KERNEL]->post( 'rrdtool', 'stop' );
        },
        _stop => sub {
             unlink('test.rrd') if -e 'test.rrd';
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

ok($ok, 'rrd dump returned some data');

exit 0;

