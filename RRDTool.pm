package POE::Component::RRDTool;
# $Id: RRDTool.pm,v 1.26 2003/09/08 16:31:42 tcaine Exp $

use strict;

use vars qw/ $VERSION $RRDTOOL_VERSION /;

$VERSION = '0.17';
$RRDTOOL_VERSION = '__RRDTOOL_VERSION__';

# library includes
use Carp;
use POE::Session;
use POE::Wheel::Run;
use POE::Driver::SysRW;
use POE::Filter::Line;
use POE::Filter::Stream;

use File::Basename qw( dirname );
use POSIX qw( :sys_wait_h );

sub IDLE () { 0 };
sub BUSY () { 1 };

#  this is the block size for POE::Driver::SysRW.  It needs to be large because the 
#  output needs to generate only one event for all different RRD commands.
#@@@@ Can this be replaced by using a custom filter for each request type?
my $block_size = 4096;

sub start_rrdtool {
    my ($kernel, $heap, %args) = @_[KERNEL, HEAP, ARG0 .. $#_];

    $kernel->alias_set('rrdtool');
    $heap->{alias} = $args{alias};
    $heap->{error_event} = $args{'error_event'} || 'rrd_error',
    $heap->{status_event} = $args{'status_event'} || 'rrd_status',
    $heap->{state} = IDLE;

    my $program = [ $args{rrdtool}, '-' ];

    $heap->{rrdtool} = POE::Wheel::Run->new(
         Program     => $program,
         ErrorEvent  => 'rrd_error',
         CloseEvent  => 'rrd_close',
         StdinEvent  => 'rrd_stdin',
         StdoutEvent => 'rrd_stdout',
         StderrEvent => 'rrd_stderr',
         StdioDriver  => POE::Driver::SysRW->new(BlockSize => $block_size),
         StdinFilter  => POE::Filter::Line->new(),
         StdoutFilter => POE::Filter::Stream->new(),
         StderrFilter => POE::Filter::Line->new(),
       );
}

sub stop_rrdtool {
    my ($kernel, $heap, $state) = @_[KERNEL, HEAP, STATE];

    if($state eq "stop") {
        if ($heap->{state} == BUSY) {
            $kernel->delay('stop', 1);
        }
        else {
            $kernel->alias_remove('rrdtool'); 
            my $alias = delete $heap->{alias};
            my $rrdtool = delete $heap->{rrdtool};
            $rrdtool->kill();
            sleep(1);        
            $rrdtool->kill( -9 );
            $kernel->post($alias, 'rrd_stopped');
        }
    }
}

sub rrd_default_handler {
    my ($heap, $state, @cmd_args) = @_[HEAP, STATE, ARG0 .. $#_];
    my $command = join(' ', $state, @cmd_args);
    $heap->{rrdtool}->put($command);
    $heap->{state} = BUSY;
}

sub rrd_output_handler {
    my ($heap, $state, @cmd_args) = @_[HEAP, STATE, ARG0 .. $#_];

    #  enqueue the callback
    push(@{$heap->{callbacks}}, shift @cmd_args);
    #  enqueue the command state info
    push(@{$heap->{cmd_state}}, $state);

    my $command = join(' ', $state, @cmd_args);
    $heap->{rrdtool}->put($command);
    $heap->{state} = BUSY;
}

sub rrd_error {
    carp( $_[ARG0] );
}

sub rrd_output {
    my ($kernel, $heap, $output) = @_[KERNEL, HEAP, ARG0];
    my $alias = $heap->{alias};
    #  figure out what RRDtool sent to STDOUT
    if ($output =~ /Usage:/) {
        $kernel->post($alias, $heap->{'error_event'}, $output);
    }
    elsif ($output =~ /ERROR:\s(.*)/) {
        $kernel->post($alias, $heap->{'error_event'}, $1);
    }
    else {
        my $output = $output;
        $output =~ s/OK .*$//ms;
        if($output) {
            #  parse the data section and post a data structure to represent the output

            #  $response contains a reference to the data structure that will be used as an 
            #  argument to the callback.  Each RRDtool command has a different output so they 
            #  need their own representation
            my $response; 

            #  each RRD command that returns data will add it's name to the cmd_state queue
            #  so that we can tell which RRD command output that needs to be parsed
            my $command_output = pop @{$heap->{cmd_state}};
            if($command_output eq 'fetch') {
                my @data = split(/\n/, $output); 
                my $header = shift @data;      # the header contains the RRD data source names
                shift @data;                   # remove blank line after the header

                my @names = $header =~ m/(\S)+/;

                #  get first two timestamps to calculate the time between each data point
                my ($time1) = $data[0] =~ m/^(\d+):/;
                my ($time2) = $data[1] =~ m/^(\d+):/;
           
                my %fetch_results = (
                    start_time => $time1,
                    step       => $time2 - $time1,
                    names      => [ @names ],
                    data       => [],
                );

                foreach (@data) {
                    my ($timestamp, @rawdata) = split(/[:\s]+/);
                    push @{$fetch_results{data}}, [ @rawdata ];
                }
    
                $response = \%fetch_results;
            }
            elsif($command_output eq 'graph') {
                my @GRAPH_output = ();
                my @output = split /\n/, $output;

                #  get rrdtool graph's GRAPH output if any
                foreach (reverse @output) {
                    if (/^(?:NaN|[\-\+\.\d]+)$/) {
                        push @GRAPH_output, $_;
                    }
                    else {
                        last;
                    }
                }

                #  get the image size
                my ($x,$y) = $output =~ m/(\d{2,3})x(\d{2,3})/;

                my %graph_results = (
                    xsize  => $x,
                    ysize  => $y,
                    output => [ @GRAPH_output ],
                );
                $response = \%graph_results;
            }
            elsif($command_output eq 'info') {
                my %info_results;
                foreach my $line (split(/\n/, $output)) {
                    my ($attribute, $value) = split(/\s=\s/, $line);
                    $value =~ s/"//g;
                    $info_results{$attribute} = $value;
                }
                $response = \%info_results;
            }
            elsif($command_output eq 'xport') {
                $response = \$output;
            }
            elsif($command_output eq 'dump') {
                $response = \$output;
            }

            my $callback = (scalar @{$heap->{callbacks}}) 
                           ? pop(@{$heap->{callbacks}})
                           : 'rrd_output';
       
            $kernel->post($alias, $callback, $response);
        }
    }

    #  update rrdtool run times
    if ($output =~ /OK u:(\d+\.\d\d) s:(\d+\.\d\d) r:(\d+\.\d\d)/) {
        $kernel->post($alias, $heap->{'status_event'}, $1, $2, $3);
    }

    $heap->{state} = IDLE;
}

sub new {
    my $class = shift;
    my %param = @_;
    my %args  = (
        alias   => 'rrdtool',
        rrdtool => '__DEFAULT_RRDTOOL__',
    );

    foreach (keys %param) {
        if    (/^-?alias$/i)      { $args{alias}       = $param{$_} }
        elsif (/^-?rrdtool$/i)    { $args{rrdtool}     = $param{$_} }
        elsif (/^-?errorevent$/i) { $args{error_event} = $param{$_} }
        elsif (/^-?statusevent$/i){ $args{status_event}= $param{$_} }
    } 

    croak "couldn't find $args{rrdtool}\n" 
        unless -e $args{rrdtool};
    
    POE::Session->create
    (   inline_states => { 
            _start     => \&start_rrdtool,
            stop       => \&stop_rrdtool,

            #  rrdtool commands
            create     => \&rrd_default_handler,
            update     => \&rrd_default_handler,
            fetch      => \&rrd_output_handler,
            graph      => \&rrd_output_handler,
            tune       => \&rrd_default_handler,
            dump       => \&rrd_default_handler,
            restore    => \&rrd_default_handler,
            info       => \&rrd_output_handler,
            xport      => \&rrd_output_handler,
            dump       => \&rrd_output_handler,

            #  rrdtool wheel run events
            rrd_error  => \&rrd_error,
            rrd_closed => \&rrd_error,
            rrd_stdout => \&rrd_output,
            rrd_stderr => \&rrd_error,

            _stop      => \&stop_rrdtool, 
        },
        args => [ %args ],
    );
}

1;
__END__

=head1 NAME

POE::Component::RRDTool - POE interface to Tobias Oetiker's RRDtool

=head1 SYNOPSIS

  use POE qw( Component::RRDTool );

  my $alias = 'controller';

  my @create_args = qw(
      test.rrd
      --start now
      --step 30
      DS:X:GAUGE:60:0:10
      RRA:MAX:0.5:1:1
  );

  # start up the rrdtool component
  POE::Component::RRDTool->new(  
      Alias      => $alias,
      RRDtool    => '/usr/local/bin/rrdtool',
      ErrorEvent => 'rrd_error',
      StatusEvent=> 'rrd_status',
  );

  POE::Session->create(
      inline_states => {
          _start => sub {
               # set a session alias so that we can receive events from RRDtool
               $_[KERNEL]->alias_set($_[ARG0]);

               # create a round robin database
               $_[KERNEL]->post( 'rrdtool', 'create', @create_args );

               # stop the rrdtool component
               $_[KERNEL]->post( 'rrdtool', 'stop' );
          },
          'rrd_error' => sub {
              print STDERR "ERROR: " . $_[ARG0] . "\n";
          },
          'rrd_status' => sub {
               my ($user, $system, $real) = @_[ARG0 .. ARG2];
               print "u: $user\ts: $system\tr: $real\n";
          },
      },
      args => [ $alias ],
  );

  $poe_kernel->run();

=head1 DESCRIPTION

RRDtool refers to round robin database tool.  Round robin databases have a fixed number of data points in them and contain a pointer to the current element.  Since the databases have a fixed number of data points the database size doesn't change after creation.  RRDtool allows you to define a set of archives which consolidate the primary data points in higher granularity.  RRDtool is specialized for time series data and can be used to create RRD files, update RRDs, retreive data from RRDs, and generate graphs from the databases.  This module provides a POE wrapper around the rrdtool command line interface.

=head1 METHODS

=over 4

=item B<new> - creates a POE RRDTool component

new() is the constructor for L<POE::Component::RRDTool>.  The constructor is L<POE::Component::RRDTool>'s only public method.  It has two optional named parameters B<alias> and B<rrdtool>.  

The B<alias> parameter is the alias of the session that the L<POE::Component::RRDTool> instance will send events to as callbacks.  It defaults to B<component>.  It is important to understand that an RRDTool instance ALWAYS uses the B<rrdtool> alias to reference itself.  Events are posted to the rrdtool alias and callbacks are posted to the alias set via the constructor.

The B<rrdtool> parameter is the name of the RRDtool command line utility.  It defaults to /usr/local/bin/rrdtool or the location that was found when building and installing on your system.  You can use the B<rrdtool> parameber to override this default location.

In the calling convention below the C<[]>s indicate optional parameters.

  POE::Component::RRDTool->new(
      [-alias       => 'controller'],
      [-rrdtool     => '/usr/local/bin/rrdtool'],
      [-errorevent  => 'error_handler'],
      [-statusevent => 'status_handler'],
  );

=back

=head1 EVENTS

L<POE::Component::RRDTool> events take the same parameters as their rrdtool counterpart.  Use the RRDtool manual as a reference for rrdtool command parameters.  

The following events can be posted to an RRDtool component.  

=over 4

=item B<create> - create a round robin database

  my @create_args = qw(
      test.rrd
      --start now
      --step 30
      DS:X:GAUGE:60:0:10
      RRA:MAX:0.5:1:1
  );

  $_[KERNEL]->post( qw( rrdtool create ), @create_args);

=item B<update> - update a round robin database

  $_[KERNEL]->post( qw( rrdtool update test.rrd N:1 ) );

=item B<fetch> - fetch data from a RRD

  my $callback = 'rrd_fetch_handler';

  my @fetch_args = qw( 
      test.rrd 
      MAX
      --start -1s
  );

  $_[KERNEL]->post( qw( rrdtool fetch ), $callback, @fetch_args );

=item B<graph> - generate a graph image from RRDs

  my $callback = 'rrd_graph_handler';

  my @graph_args = (
      'graph.png',
      '--start', -86400,
      '--imgformat', 'PNG',
      'DEF:x=test.rrd:X:MAX',
      'CDEF:y=1,x,+',
      'PRINT:y:MAX:%lf',
      'AREA:x#00FF00:test_data',
  );

  $_[KERNEL]->post( qw( rrdtool udpate ), $callback, @graph_args );

  sub rrd_graph_handler {
      my $graph = $_[ARG0];
      printf("Image Size: %dx%d\n", $graph->{xsize}, $graph->{ysize});
      printf("PRINT output: %s\n", join('\n', @$graph->{output}) if @$graph;
      print "graph.png was created" if -e "graph.png";
      warn "no image was created" unless -e "graph.png";
  }

=item B<info> - get information about a RRD

  my $callback = 'rrd_info_handler';

  $_[KERNEL]->post( qw( rrdtool info ), $callback, 'test.rrd' );

=item B<xport> - generate xml reports from RRDs

  my $callback = 'rrd_xport_handler';

  my @xport_args = (
    '--start', -300,
    '--step', 300,
    'DEF:x=test.rrd:X:MAX',
    'XPORT:x:foobar',
  );

  $_[KERNEL]->post( qw( rrdtool xport ), $callback, @xport_args );

=item B<dump> - dump a RRD in XML format

  my $callback = 'rrd_dump_handler';

  $_[KERNEL]->post( qw( rrdtool dump ), $callback, 'test.rrd' );

=item B<stop> - stop an RRDTool component

  $_[KERNEL]->post( qw( rrdtool stop ) );

=back

=head1 CALLBACKS

The callbacks listed below are sent by the RRDTool component to the session alias passed to it's constructor.  You can provide event handlers for them in the controlling session's constructor.  However it is not required to handle any of the callbacks.

=over 4 

=item B<rrd_status> - notification of rrdtool runtimes

Returns the user, system, and real time of the rrdtool process in ARG0, ARG1, and ARG2 respectively.  This event name can be overriden by using the StatusEvent parameter to POE::Component::RRDTool->new();

  POE::Session->create(
    inline_states => {
      'rrd_status' => sub {
        my ($user, $system, $real) = @_[ARG0 .. ARG2];
        print "u: $user\ts: $system\tr: $real\n";
      },
      ....,
    }
  );

=item B<rrd_error> - rrdtool error notification

Returns error messages returned from rrdtool in ARG0.

  POE::Session->create(
    inline_states => {
      'rrd_error' => sub {
        my $error = $_[ARG0];
        print "Error: $error\n";
      },
      ....,
    }
  );

=item B<rrd_stopped> - rrdtool process stopped

This callback provides a hook to do something when the rrdtool process is stopped.

  POE::Session->create(
    inline_states => {
      'rrd_stopped' => sub {
        print "rrdtool stopped\n";
      },
      ....,
    }
  );

=back

=head1 AUTHOR

Todd Caine  <todd@pobox.com>

=head1 SEE ALSO

An RRDtool Tutorial
http://people.ee.ethz.ch/~oetiker/webtools/rrdtool/tutorial/rrdtutorial.html

The Main RRDtool Website
http://people.ee.ethz.ch/~oetiker/webtools/rrdtool/index.html

The RRDtool Manual
http://people.ee.ethz.ch/~oetiker/webtools/rrdtool/manual/index.html

=head1 TROUBLESHOOTING

The rrdtool command line utility does not support the xport subcommand until version 1.0.38.  If you try to use the xport event using an older version of rrdtool you will receive an rrdtool usage message as an rrd_error callback.

=head1 BUGS

The rrdtool command line utility is being controlled by POE::Wheel::Run.  I'm increasing the block size on the POE::Driver::SysRW instance used for the rrdtool output so that each command generates only one event.  This should probably be fixed by using the default block size and a custom filter instead.  

If you notice that more than one event is being generated from a single rrdtool command you may need to increase the blocksize used.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2003 Todd Caine.  All rights reserved. This program is free 
software; you can redistribute it and/or modify it under the same terms
as Perl itself.

=cut
