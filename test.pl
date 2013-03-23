#!/usr/bin/perl -w

# for test MBclient perl module

use strict;
use MBclient;

# create modbus object
my $mb = MBclient->new();
# on local modbus server
$mb->{HOST}  = '127.0.0.1';
$mb->unit_id(1);
# for print frame and debug string : uncomment this line
#$mb->{debug} = 1;

# write regiter 0 to 9 with value from 0 to 90
my $i = 0;
while($i < 10) {
  $mb->write_single_register($i, $i*10);
  $i++;
}

# read register 0 to 9
my $words = $mb->read_holding_registers(0, 10);
foreach my $word (@$words) {
  print $word."\n";
}
