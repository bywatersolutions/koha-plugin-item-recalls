#!/usr/bin/perl

use Modern::Perl;

use C4::Context;
use lib C4::Context->config("pluginsdir");

use Koha::Plugin::Com::ByWaterSolutions::ItemRecalls;

my $plugin = Koha::Plugin::Com::ByWaterSolutions::ItemRecalls->new();
$plugin->cronjob();
