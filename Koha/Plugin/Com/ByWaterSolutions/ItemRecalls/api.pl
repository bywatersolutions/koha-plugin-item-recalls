#!/usr/bin/perl

use Modern::Perl;

use CGI;

use C4::Context;
use lib C4::Context->config("pluginsdir");

use Koha::Plugin::Com::ByWaterSolutions::ItemRecalls;

my $cgi = new CGI;

my $plugin = Koha::Plugin::Com::ByWaterSolutions::ItemRecalls->new({ cgi => $cgi });
$plugin->api();
