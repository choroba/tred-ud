#!/usr/bin/perl
use warnings;
use strict;

BEGIN { $^I = '~' }

use open OUT => ':encoding(UTF-8)', ':std';

use XML::LibXML;

my $package = 'XML::LibXML'->load_xml(location => 'ud/package.xml');
my $xpc = 'XML::LibXML::XPathContext'->new;
$xpc->registerNs(pml => 'http://ufal.mff.cuni.cz/pdt/pml/');
my $copyright = ($xpc->findnodes('/pml:tred_extension/pml:copyright',
                                 $package))[0];

while (<>) {
    if (/Copyright ([-0-9]+) \w+/) {
        print "Copyright ";
        print $copyright->{year};
        print ' ';
        print $copyright->textContent;
        print "\n";
    } else {
        print;
    }
}
