
use strict;

sub POE::Kernel::ASSERT_ALL () { 1 }

use POE;

use lib qw(../blib/arch ../blib/lib);
use POE::Component::RRDTool;

use Test::More tests => 1;

#---------------------#
#  Test 9: RRD error   #
#---------------------#

my $ok = 0;

my @dump_args = qw( test.rrd );

my $alias = 'controller';
POE::Component::RRDTool->new(
    -alias      => $alias,
    -rrdtool    => '/usr/local/bin/rrdtool',
    -errorevent => 'error_handler',
);

POE::Session->create(
    'inline_states' => {
        '_start' => sub { 
            $_[KERNEL]->alias_set($_[ARG0]);
            $_[KERNEL]->post( 'rrdtool', 'create', 'nothing' );
            $_[KERNEL]->post( 'rrdtool', 'stop' );
        },
        'error_handler' => sub { $ok = 1 },
    },
    'args' => [ $alias ],
);

$poe_kernel->run();

ok($ok, 'error event triggered on bogus input');

exit 0;

