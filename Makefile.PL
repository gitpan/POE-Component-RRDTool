use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'         => 'POE::Component::RRDTool',
    'VERSION_FROM' => 'RRDTool.pm',
    'PREREQ_PM'    => {
        'POE' => '0.22',
    },
    (($] ge '5.005') ? 
        (   'AUTHOR'   => 'Todd Caine <todd@pobox.com>',
            'ABSTRACT' => 'POE interface to Tobias Oetiker\'s RRDTool',
        ) : (),
    ),
);
