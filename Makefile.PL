use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Ingres::Utility::Netutil',
    AUTHOR              => 'Joner Cyrre Worm <FAJCNLXLLXIH@spammotel.com>',
    VERSION_FROM        => 'lib/Ingres/Utility/Netutil.pm',
    ABSTRACT_FROM       => 'lib/Ingres/Utility/Netutil.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'Expect::Simple'    => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Ingres-Utility-Netutil-*' },
);
