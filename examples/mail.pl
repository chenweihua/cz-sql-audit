#!/usr/bin/env perl

use strict;
use warnings;
use SQL::Audit::Email::Send;
my @mail = ('chenzhe07@gmail.com');
my $smtp = SQL::Audit::Email::Send->new(
    subject  => 'SQL audit message.',
    mailto   => \@mail,
    mailfrom => 'sql_audit@pwrd.com',
);

my @msg;
push @msg, 'mail test';
push @msg, 'warnings query.';
$smtp->send( @msg );
