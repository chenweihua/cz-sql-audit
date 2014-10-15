#!/usr/bin/env perl
use Data::Dumper;
use strict;
use warnings;
use SQL::Log::Record;

my $log = SQL::Log::Record->new(
    'filename' => './logs/audits.log',
    'mode'     => '>>',
);

my @msg;
push @msg, 'master status';
push @msg, 'slave status';

$log->debug(\@msg);
$log->error("hello world");
