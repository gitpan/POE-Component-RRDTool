#!/usr/local/bin/perl -w

use strict;

sub POE::Kernel::ASSERT_ALL () { 1 }

use POE;

use lib qw(../blib/arch ../blib/lib);
use POE::Component::RRDTool;

use Test::More tests => 1;

#----------------------------------#
#  Test 1: starting and stopping   #
#----------------------------------#

my $loaded = 0;

my $alias = 'controller';
POE::Component::RRDTool->new(
    -alias   => $alias,
    -rrdtool => '/usr/local/bin/rrdtool',
);

POE::Session->create(
    inline_states => {
        _start => sub { 
             $_[KERNEL]->alias_set($_[ARG0]);
             $_[KERNEL]->post( qw( rrdtool stop ) ) 
        },
        rrd_stopped => sub { $loaded = 1 },
    },
    args => [ $alias ],
);

$poe_kernel->run();

ok($loaded);

exit 0;
