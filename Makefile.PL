use ExtUtils::MakeMaker;

my @SEARCH_PATH = (glob('/usr/local/rrdtool*'), glob('/usr/rrdtool*'), glob('/opt/rrdtool*'));

#  search for the rrdtool binary
my $DEFAULT_RRDTOOL = '/usr/local/bin/rrdtool';

$DEFAULT_RRDTOOL = &find_rrdtool_binary() 
   unless -e $DEFAULT_RRDTOOL;

$DEFAULT_RRDTOOL = prompt('enter the full path to the rrdtool binary: ', $DEFAULT_RRDTOOL);

die "$DEFAULT_RRDTOOL does not exist." 
    unless -e $DEFAULT_RRDTOOL;

my ($RRDTOOL_VERSION) = `$DEFAULT_RRDTOOL -v` =~ /^RRDtool (\d+\.\d+\.\d+) /;

WriteMakefile(
    'NAME'         => 'POE::Component::RRDTool',
    'VERSION_FROM' => 'RRDTool.pm',
    'PREREQ_PM'    => {
        'POE' => '0.22',
    },
    PM_FILTER => "sed -e s\\#__DEFAULT_RRDTOOL__\\#${DEFAULT_RRDTOOL}\\#g -e s\\#__RRDTOOL_VERSION__\\#${RRDTOOL_VERSION}\\#g",
    (($] ge '5.005') ? 
        (   'AUTHOR'   => 'Todd Caine <todd@pobox.com>',
            'ABSTRACT' => 'POE interface to Tobias Oetiker\'s RRDTool',
        ) : (),
    ),
);

sub find_rrdtool_binary {
    my $newest = &find_newest_version( @SEARCH_PATH );
    $newest .= '/bin/rrdtool';
    return '' unless -e $newest;
    return $newest;
}

sub find_newest_version {
    my @rrdtool_dirs = 
        map  { $_->[0] }
        sort { $a->[1] <=> $b->[1] || $a->[2] <=> $b->[2] || $a->[3] <=> $b->[3] }
        map  {my ($maj, $min, $sub) =~ /rrdtool\-(\d+)\.(\d+)\.(\d+)/; [$_, $1, $2, $3]}
        @_;
    return pop @rrdtool_dirs;
}

