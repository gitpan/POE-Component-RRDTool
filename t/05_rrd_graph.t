#!/usr/local/bin/perl -w

use strict;

sub POE::Kernel::ASSERT_ALL () { 1 }

use POE;

use lib qw(../blib/arch ../blib/lib);
use POE::Component::RRDTool;

use Test::More tests => 1;

#----------------------#
#  Test 5: RRD graph   #
#----------------------#

my $ok = 0;

my @graph_args = (
    '-',
    '--start', -86400,
    '--imgformat', 'PNG',
    'DEF:x=test.rrd:X:MAX',
    'AREA:x#00FF00:test_data',
);

my $alias = 'controller';
POE::Component::RRDTool->new(
    -alias   => $alias,
    -rrdtool => '/usr/local/bin/rrdtool',
);

POE::Session->create(
    inline_states => {
        _start => sub { 
            $_[KERNEL]->alias_set($_[ARG0]);
            $_[KERNEL]->post( 'rrdtool', 'graph', 'get_value', @graph_args );
            $_[KERNEL]->post( 'rrdtool', 'stop' );
        },
        _stop => sub {
            unlink('test.png') if -e 'test.png';
        },
        'get_value' => sub {
            my $output = $_[ARG0];
            $ok = 1 if $$output;

            # write image to disk
            open(IMG, "> test.png") or die "can't write test.png: $!\n";
            binmode(IMG);
            print IMG $$output;
            close(IMG);
        },
        'rrd_error' => sub { 
            $ok = 0; 
            print STDERR "ERROR: " . $_[ARG0] . "\n";  
        },
    },
    args => [ $alias ],
);

$poe_kernel->run();

ok($ok);

exit 0;

