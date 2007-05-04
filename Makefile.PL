

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME         => 'WebService::CRUST',
    VERSION_FROM => 'lib/WebService/CRUST.pm', # finds \$VERSION
    AUTHOR       => 'Chris Heschong (chris@wiw.org)',
    ABSTRACT     => 'A lightweight Client for making REST calls',
    PREREQ_PM    => {
                     'Test::Simple' => 0.44,
                     'XML::Simple' => 2.16,
                    },
);
