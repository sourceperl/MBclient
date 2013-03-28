#!/usr/bin/perl -w

# for test MBclient perl module

use strict;
use MBclient;

# create modbus object
my $mb = MBclient->new();

# on local modbus server
$mb->host("127.0.0.1");
$mb->unit_id(1);
# for print frame and debug string : uncomment this line
#$mb->{debug} = 1;

# open TCP socket
if (! $mb->open()) {
  print "unable to open TCP socket.\n";
  exit(1);
}

# read register 0 to 9 and print it on stdout
my $words = $mb->read_holding_registers(0, 10);
foreach my $word (@$words) {
  print $word."\n";
}
