#!/usr/local/bin/perl -w

use strict;

sub POE::Kernel::ASSERT_ALL () { 1 }

use POE;

use lib qw(../blib/arch ../blib/lib);
use POE::Component::RRDTool;

use Test::More tests => 1;

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
    -alias   => $alias,
    -rrdtool => '/usr/local/bin/rrdtool',
);

POE::Session->create(
    inline_states => {
        _start => sub { 
             $_[KERNEL]->alias_set($_[ARG0]);
             $_[KERNEL]->post( 'rrdtool', 'create', @create_args );
             $_[KERNEL]->post( 'rrdtool', 'stop' );
        },
        'rrd_error' => sub {
            print STDERR "ERROR: " . $_[ARG0] . "\n";
        }
    },
    args => [ $alias ],
);

$poe_kernel->run();

my $created = -e "./test.rrd";
ok($created);

exit 0;
