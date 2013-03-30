# Perl module: Client ModBus / TCP class 1
#     Version: 1.4.2
#     Website: http://source.perl.free.fr (in french)
#        Date: 23/03/2013
#     License: GPL v3 (http://www.gnu.org/licenses/quick-guide-gplv3.en.html)
# Description: Client ModBus / TCP command line
#              Support functions 3 and 16 (class 0)
#              1,2,4,5,6 (Class 1)
#     Charset: us-ascii, unix end of line

# todo
#   - add support for MEI function
# 

package MBclient;

## Required Modules

use 5.005;
use strict;
use vars qw($AUTOLOAD $VERSION @ISA @EXPORT);
use Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(MODBUS_TCP MODBUS_RTU
             EXP_ILLEGAL_FUNCTION EXP_DATA_ADDRESS EXP_DATA_VALUE
             EXP_SLAVE_DEVICE_FAILURE  EXP_ACKNOWLEDGE EXP_SLAVE_DEVICE_BUSY
             EXP_MEMORY_PARITY_ERROR EXP_GATEWAY_PATH_UNAVAILABLE 
             EXP_GATEWAY_TARGET_DEVICE_FAILED_TO_RESPOND
             MB_NO_ERR MB_RESOLVE_ERR MB_CONNECT_ERR MB_SEND_ERR
             MB_RECV_ERR MB_TIMEOUT_ERR MB_FRAME_ERR MB_EXCEPT_ERR);
use Socket;
use bytes;

$VERSION = '1.4.2';

##
## Constant
##

## ModBus/TCP
use constant MODBUS_PORT                                 => 502;
## ModBus RTU
use constant FRAME_RTU_MAXSIZE                           => 512;
## Modbus mode
use constant MODBUS_TCP                                  => 1;
use constant MODBUS_RTU                                  => 2;
## Modbus function code
# standard
use constant READ_COILS                                  => 0x01;
use constant READ_DISCRETE_INPUTS                        => 0x02;
use constant READ_HOLDING_REGISTERS                      => 0x03;
use constant READ_INPUT_REGISTERS                        => 0x04;
use constant WRITE_SINGLE_COIL                           => 0x05;
use constant WRITE_SINGLE_REGISTER                       => 0x06;
use constant WRITE_MULTIPLE_REGISTERS                    => 0x10;
use constant MODBUS_ENCAPSULATED_INTERFACE               => 0x2B;
## Modbus except code
use constant EXP_ILLEGAL_FUNCTION                        => 0x01;
use constant EXP_DATA_ADDRESS                            => 0x02;
use constant EXP_DATA_VALUE                              => 0x03;
use constant EXP_SLAVE_DEVICE_FAILURE                    => 0x04;
use constant EXP_ACKNOWLEDGE                             => 0x05;
use constant EXP_SLAVE_DEVICE_BUSY                       => 0x06;
use constant EXP_MEMORY_PARITY_ERROR                     => 0x08;
use constant EXP_GATEWAY_PATH_UNAVAILABLE                => 0x0A;
use constant EXP_GATEWAY_TARGET_DEVICE_FAILED_TO_RESPOND => 0x0B;
## Module error codes
use constant MB_NO_ERR                                   => 0;
use constant MB_RESOLVE_ERR                              => 1;
use constant MB_CONNECT_ERR                              => 2;
use constant MB_SEND_ERR                                 => 3;
use constant MB_RECV_ERR                                 => 4;
use constant MB_TIMEOUT_ERR                              => 5;
use constant MB_FRAME_ERR                                => 6;
use constant MB_EXCEPT_ERR                               => 7;


##
## Constructor.
##

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = {};
  ##
  ## UPPERCASE items have documented accessor functions.
  ## lowercase items are reserved for internal use.
  ##
  $self->{VERSION}       = $VERSION;          # version number
  $self->{HOST}          = undef;             # 
  $self->{PORT}          = MODBUS_PORT;       # 
  $self->{UNIT_ID}       = 1;                 # 
  $self->{LAST_ERROR}    = MB_NO_ERR;         # last error code   
  $self->{LAST_EXCEPT}   = 0;                 # last expect code   
  $self->{MODE}          = MODBUS_TCP;        # by default modbus/tcp
  $self->{sock}          = undef;             # socket handle
  $self->{timeout}       = 30;                # socket timeout
  $self->{hd_tr_id}      = 0;                 # store transaction ID
  $self->{debug}         = 0;                 # enable debug trace
  # object bless
  bless $self, $class;
  return $self;
}

##
## Get current version number.
##

sub version {
  my $self = shift;
  return $self->{VERSION};
}

##
## Get last error code.
##

sub last_error {
  my $self = shift;
  return $self->{LAST_ERROR};
}

##
## Get last except code.
##

sub last_except {
  my $self = shift;
  return $self->{LAST_EXCEPT};
}

##
## Get or set host field (IPv4 or hostname like "plc.domain.net").
##

sub host {
  my $self = shift;
  my $hostname  = shift;
  # return last hostname if no arg
  return $self->{HOST} unless defined $hostname;
  # if host is IPv4 address or valid URL
  if (($hostname =~ m/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) or 
      ($hostname =~ m/^[a-z][a-z0-9\.\-]+$/)) {
    $self->{HOST} = $hostname;
  }
  return $self->{HOST};
}

##
## Get or set TCP port field.
##

sub port {
  my $self = shift;
  my $port  = shift;
  # return last hostname if no arg
  return $self->{PORT} unless defined $port;
  # if host is IPv4 address or valid URL
  if (($port =~ m/^\d{1,5}$/) and 
      ($port < 65536)) {
    $self->{PORT} = $port;
  }
  return $self->{PORT};
}

##
## Get or set unit_id field.
##

sub unit_id {
  my $self = shift;
  my $uid  = shift;
  # return unit_id if no arg
  return $self->{UNIT_ID} unless defined $uid;
  # if uid is numeric, set unit_id
  if ($uid =~ m/^\d{1,3}$/) {
   $self->{UNIT_ID} = $uid;
  }
  return $self->{UNIT_ID};
}

##
## Get or set modbus mode (TCP or RTU).
##

sub mode {
  my $self = shift;
  my $mode  = shift;
  # return mode if no arg
  return $self->{MODE} unless defined $mode;
  # set mode and return mode
  $self->{MODE} = $mode;
  return $self->{MODE};
}

##
## Open TCP link.
##

sub open {
  my $self = shift;
  print 'call open()'."\n" if ($self->{debug});
  # restart TCP if already open
  $self->close if ($self->is_open);
  # name resolve
  my $ad_ip = inet_aton($self->{HOST});
  unless($ad_ip) {
    $self->{LAST_ERROR} = MB_RESOLVE_ERR;
    print 'IP resolve error'."\n" if ($self->{debug});
    return undef;
  }
  # set socket
  socket($self->{sock}, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
  my $connect_ok = connect($self->{sock}, sockaddr_in($self->{PORT}, $ad_ip));
  if ($connect_ok) {
    return 1;
  } else {
    $self->{sock} = undef;
    $self->{LAST_ERROR} = MB_CONNECT_ERR;
    print 'TCP connect error'."\n" if ($self->{debug});
    return undef;
  }
};

##
## Check TCP link.
##

sub is_open {
  my $self = shift;
  return (defined $self->{sock});
};

##
## Close TCP link.
##

sub close {
  my $self = shift;
  if ($self->{sock}) { 
    close $self->{sock};
    $self->{sock} = undef;
    return 1;
  } else {
    return undef;
  }
};

##
## Modbus function READ_COILS (0x01).
##   read_coils(bit_addr, bit_number)
##   return a ref to result array
##          or undef if error

sub read_coils {
  my $self     = shift;
  my $bit_addr = shift;
  my $bit_nb   = shift;
  # build frame
  my $tx_buffer = $self->_mbus_frame(READ_COILS, pack("nn", $bit_addr, $bit_nb));
  # send request
  my $s_send = $self->_send_mbus($tx_buffer);
  # check error
  return undef unless ($s_send);
  # receive
  my $f_body = $self->_recv_mbus();
  # check error
  return undef unless ($f_body);
  # register extract
  my ($rx_byte_count, $f_bits) = unpack 'Cb*', $f_body;
  # read bit(s) string
  my @bits = split //, $f_bits;
  $#bits = $bit_nb - 1;
  return \@bits;
}

##
## Modbus function READ_DISCRETE_INPUTS (0x02).
##   read_discrete_inputs(bit_addr, bit_number)
##   return a ref to result array
##          or undef if error

sub read_discrete_inputs {
  my $self     = shift;
  my $bit_addr = shift;
  my $bit_nb   = shift;
  # build frame
  my $tx_buffer = $self->_mbus_frame(READ_DISCRETE_INPUTS, pack("nn", $bit_addr, $bit_nb));
  # send request
  my $s_send = $self->_send_mbus($tx_buffer);
  # check error
  return undef unless ($s_send);
  # receive
  my $f_body = $self->_recv_mbus();
  # check error
  return undef unless ($f_body);
  # register extract
  my ($rx_byte_count, $f_bits) = unpack 'Cb*', $f_body;
  # read bit(s) string
  my @bits = split //, $f_bits;
  $#bits = $bit_nb - 1;
  return \@bits;
}


##
## Modbus function READ_HOLDING_REGISTERS (0x03).
##   read_holding_registers(reg_addr, reg_number)
##   return a ref to result array
##          or undef if error

sub read_holding_registers {
  my $self     = shift;
  my $reg_addr = shift;
  my $reg_nb   = shift;
  # build frame
  my $tx_buffer = $self->_mbus_frame(READ_HOLDING_REGISTERS, pack("nn", $reg_addr, $reg_nb));
  # send request
  my $s_send = $self->_send_mbus($tx_buffer);
  # check error
  return undef unless ($s_send);
  # receive
  my $f_body = $self->_recv_mbus();
  # check error
  return undef unless ($f_body);
  # register extract
  my ($rx_reg_count, $f_regs) = unpack 'Ca*', $f_body;
  # read 16 bits register
  my @registers = unpack 'n*', $f_regs;
  return \@registers;
}

##
## Modbus function READ_INPUT_REGISTERS (0x04).
##   read_input_registers(reg_addr, reg_number)
##   return a ref to result array
##          or undef if error

sub read_input_registers {
  my $self     = shift;
  my $reg_addr = shift;
  my $reg_nb   = shift;
  # build frame
  my $tx_buffer = $self->_mbus_frame(READ_INPUT_REGISTERS, pack("nn", $reg_addr, $reg_nb));
  # send request
  my $s_send = $self->_send_mbus($tx_buffer);
  # check error
  return undef unless ($s_send);
  # receive
  my $f_body = $self->_recv_mbus();
  # check error
  return undef unless ($f_body);
  # register extract
  my ($rx_reg_count, $f_regs) = unpack 'Ca*', $f_body;
  # read 16 bits register
  my @registers = unpack 'n*', $f_regs;
  return \@registers;
}

##
## Modbus function WRITE_SINGLE_COIL (0x05).
##   write_single_coil(bit_addr, bit_value)
##   return 1 if write success
##          or undef if error

sub write_single_coil {
  my $self      = shift;
  my $bit_addr  = shift;
  my $bit_value = shift;
  # build frame
  $bit_value = ($bit_value) ? 0xFF : 0;
  my $tx_buffer = $self->_mbus_frame(WRITE_SINGLE_COIL, pack("nC", $bit_addr, $bit_value));
  # send request
  my $s_send = $self->_send_mbus($tx_buffer);
  # check error
  return undef unless ($s_send);
  # receive
  my $f_body = $self->_recv_mbus();
  # check error
  return undef unless ($f_body);
  # register extract
  my ($rx_bit_addr, $rx_bit_value) = unpack 'nC', $f_body;
  # check bit write
  return (($rx_bit_addr == $bit_addr) and ($rx_bit_value == $bit_value)) ? 1 : undef;
}

##
## Modbus function WRITE_SINGLE_REGISTER (0x06).
##   write_single_register(reg_addr, reg_value)
##   return 1 if write success
##          or undef if error

sub write_single_register {
  my $self      = shift;
  my $reg_addr  = shift;
  my $reg_value = shift;
  # build frame
  my $tx_buffer = $self->_mbus_frame(WRITE_SINGLE_REGISTER, pack("nn", $reg_addr, $reg_value));
  # send request
  my $s_send = $self->_send_mbus($tx_buffer);
  # check error
  return undef unless ($s_send);
  # receive
  my $f_body = $self->_recv_mbus();
  # check error
  return undef unless ($f_body);
  # register extract
  my ($rx_reg_addr, $rx_reg_value) = unpack 'nn', $f_body;
  # check bit write
  return (($rx_reg_addr == $reg_addr) and ($rx_reg_value == $reg_value)) ? 1 : undef;
}

##
## Modbus function WRITE_MULTIPLE_REGISTERS (0x10).
##   write_multiple_registers(reg_addr, ref_to_reg_array)
##   return 1 if write success
##          or undef if error

sub write_multiple_registers {
  my $self          = shift;
  my $reg_addr      = shift;
  my $ref_array_reg = shift;
  my @reg_value     = @$ref_array_reg;
  # build frame
  # register
  my $reg_nb = @reg_value;
  # format reg value string
  my $reg_val_str;
  for (@reg_value) {$reg_val_str .= pack("n", $_);}
  my $bytes_nb = bytes::length($reg_val_str);
  # format modbus frame body
  my $body = pack("nnC", $reg_addr, $reg_nb, $bytes_nb).$reg_val_str;
  my $tx_buffer = $self->_mbus_frame(WRITE_MULTIPLE_REGISTERS, $body);
  # send request
  my $s_send = $self->_send_mbus($tx_buffer);
  # check error
  return undef unless ($s_send);
  # receive
  my $f_body = $self->_recv_mbus();
  # check error
  return undef unless ($f_body);
  # register extract
  my ($rx_reg_addr, $rx_reg_nb) = unpack 'nn', $f_body;
  # check regs write
  return ($rx_reg_addr == $reg_addr) ? 1 : undef;
}

# Build modbus frame.
#   _mbus_frame(function code, body)
#   return modbus frame
sub _mbus_frame {
  my $self  = shift;
  my $fc    = shift;
  my $body  = shift;
  # build frame body
  my $f_body = pack("C", $fc).$body;
  # modbus/TCP
  if ($self->{MODE} == MODBUS_TCP) {
    # build frame ModBus Application Protocol header (mbap)
    $self->{hd_tr_id}    = int(rand 65535);
    my $tx_hd_pr_id      = 0;
    my $tx_hd_length     = bytes::length($f_body) + 1;
    my $f_mbap = pack("nnnC", $self->{hd_tr_id}, $tx_hd_pr_id,
                              $tx_hd_length, $self->{UNIT_ID});
    return $f_mbap.$f_body;
  # modbus RTU
  } elsif ($self->{MODE} == MODBUS_RTU) {
    # format [slave addr(unit_id)]frame_body[CRC16]
    my $slave_ad = pack("C", $self->{UNIT_ID});
    return $self->_add_crc($slave_ad.$f_body);
  } else {
  # unknow mode
    return undef;
  }
}

# Send modbus frame.
#   _send_mbus(frame)
#   return $nb_byte send 
sub _send_mbus {
  my $self  = shift;
  my $frame = shift;
  # send request
  my $bytes_send = $self->_send($frame);
  return undef unless ($bytes_send);
  # for debug
  $self->_pretty_dump('Tx', $frame) if ($self->{debug});
  # return
  return $bytes_send;
}

# Recv modbus frame.
#   _recv_mbus()
#   return body (after func. code) 
sub _recv_mbus {
  my $self  = shift;
  ## receive
  # vars
  my ($rx_buffer,$rx_frame);
  my ($rx_unit_id, $rx_bd_fc, $f_body);
  # modbus TCP receive
  if ($self->{MODE} == MODBUS_TCP) {
    # 7 bytes head
    $rx_buffer = $self->_recv(7);
    return undef unless($rx_buffer);
    $rx_frame = $rx_buffer;
    # decode
    my ($rx_hd_tr_id, $rx_hd_pr_id, $rx_hd_length, $rx_hd_unit_id) = unpack "nnnC", $rx_frame;
    # check
    if (!(($rx_hd_tr_id == $self->{hd_tr_id}) && ($rx_hd_pr_id == 0) &&
          ($rx_hd_length < 256) && ($rx_hd_unit_id == $self->{UNIT_ID}))) {
      $self->close;
      return undef;
    }
    # end of frame
    $rx_buffer = $self->_recv($rx_hd_length-1);
    return undef unless($rx_buffer);
    $rx_frame .= $rx_buffer;
    # dump frame
    $self->_pretty_dump('Rx', $rx_frame) if ($self->{debug});
    # body decode
    ($rx_bd_fc, $f_body) = unpack "Ca*", $rx_buffer;
  # modbus RTU receive
  } elsif ($self->{MODE} == MODBUS_RTU) {   
    $rx_buffer = $self->_recv(FRAME_RTU_MAXSIZE);
    return undef unless($rx_buffer);
    $rx_frame = $rx_buffer;
    # dump frame
    $self->_pretty_dump('Rx', $rx_frame) if ($self->{debug});
    # body decode
    ($rx_unit_id, $rx_bd_fc, $f_body) = unpack "CCa*", $rx_frame;
    # check
    if (!($rx_unit_id == $self->{UNIT_ID})) {
      $self->close;
      return undef;
    }
  }  
  # check except
  if ($rx_bd_fc > 0x80) {
    # except code
    my ($exp_code) = unpack "C", $f_body;
    $self->{LAST_ERROR}  = MB_EXCEPT_ERR;
    $self->{LAST_EXCEPT} = $exp_code;
    print 'except (code '.$exp_code.')'."\n" if ($self->{debug});
    return undef;
  } else {
    # return
    return $f_body;
  }
}

# Send data over current socket.
#   _send(data_to_send)
#   return the number of bytes send
#          or undef if error
sub _send {
  my $self = shift;
  my $data = shift;
  # check link, open if need
  unless ($self->is_open) {
    print 'call _send() not open -> call open()'."\n" if ($self->{debug});
    return undef unless ($self->open);
  }
  # send data
  my $data_l = bytes::length($data);
  my $send_l = send($self->{sock}, $data, 0);
  # send error
  if ($send_l != $data_l) {
    $self->{LAST_ERROR} = MB_SEND_ERR;
    print '_send error'."\n" if ($self->{debug});
    $self->close;
    return undef;
  } else {
    return $send_l;
  }
}

# Recv data over current socket.
#   _recv(max_size)
#   return the receive buffer
#          or undef if error
sub _recv {
  my $self     = shift;
  my $max_size = shift;
  # wait for read
  unless ($self->_can_read()) {
    $self->close;
    return undef;
  }
  # recv
  my $buffer;
  my $s_recv = recv($self->{sock}, $buffer, $max_size, 0);
  unless (defined $s_recv) {
    $self->{LAST_ERROR} = MB_RECV_ERR;
    print '_recv error'."\n" if ($self->{debug});
    $self->close;
    return undef;
  }
  return $buffer;
}

# Wait for socket read.
sub _can_read {
  my $self  = shift;
  my $hdl_select = "";
  vec($hdl_select, fileno($self->{sock}), 1) = 1;
  my $_select = select($hdl_select, undef, undef, $self->{timeout});
  if ($_select) {
    return $_select;
  } else {  
    $self->{LAST_ERROR} = MB_TIMEOUT_ERR;
    print 'timeout error'."\n" if ($self->{debug});
    $self->close;
    return undef;
  }
}

# Compute modbus CRC16 (for RTU mode).
#   _crc(modbus_frame)
#   return the CRC
sub _crc {
  my $self  = shift;
  my $frame = shift;
  my $crc = 0xFFFF;
  my ($chr, $lsb);
  for my $i (0..bytes::length($frame)-1) {
    $chr = ord(bytes::substr($frame, $i, 1));
    $crc ^= $chr;
    for (1..8) {
      $lsb = $crc & 1;
      $crc >>= 1;
      $crc ^= 0xA001 if $lsb;
      }
    }
  return $crc;
}

# Add CRC to modbus frame (for RTU mode).
#   _add_crc(modbus_frame)
#   return modbus_frame_with_crc
sub _add_crc {
  my $self  = shift;
  my $frame = shift;
  my $crc = pack 'v', $self->_crc($frame);
  return $frame.$crc;
}

# Check the CRC of modbus RTU frame.
#   _crc_is_ok(modbus_frame_with_crc)
#   return true if CRC is ok
sub _crc_is_ok {
  my $self  = shift;
  my $frame = shift;
  my $crc = unpack('v', bytes::substr($frame, -2));
  return ($crc == $self->_crc($frame));
}

# Print modbus/TCP frame ("[header]body") or modbus RTU ("body[CRC]").
sub _pretty_dump {
  my $self  = shift;
  my $label = shift;
  my $data  = shift;
  my @dump = map {sprintf "%02X", $_ } unpack("C*", $data);
  # format for TCP or RTU
  if ($self->{MODE} == MODBUS_TCP) {
    $dump[0] = "[".$dump[0];
    $dump[5] = $dump[5]."]";
  } elsif ($self->{MODE} == MODBUS_RTU) {
    $dump[$#dump-1] = "[".$dump[$#dump-1];
    $dump[$#dump] = $dump[$#dump]."]";
  }
  # print result
  print $label."\n";
  for (@dump) {print $_." ";}
  print "\n\n";
}

1;

__END__

