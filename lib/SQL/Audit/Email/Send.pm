package SQL::Audit::Email::Send;
# send mail with provide message.
# zhe.chen<chenzhe07@gmail.com>

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use Net::SMTP;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

require Exporter;
@ISA = qw(Exporter);
@EXPORT    = qw( send );
@EXPORT_OK = qw( send_smtp );
$VERSION = '0.1.0';

eval {
    require Authen::SASL;
};

if ( $@ ) {
    warn "need Authen::SASL, install with perl-Authen-SASL: $@";
}

sub mailuser {
    my $self = shift;
    $self->{mailuser} = shift if @_;
    return $self->{mailuser};
}

sub mailpass {
    my $self = shift;
    $self->{mailpass} = shift if @_;
    return $self->{mailpass};
}

sub host {
    my $self = shift;
    $self->{host} = shift if @_;
    return $self->{host};
}

sub helo {
    my $self = shift;
    $self->{helo} = shift if @_;
    return $self->{helo};
}

sub subject {
    my $self = shift;
    $self->{subject} = shift if @_;
    return $self->{subject};
}

sub mailfrom {
    my $self = shift;
    $self->{mailfrom} = shift if @_;
    return $self->{mailfrom};
}

sub mailto {
    my $self = shift;
    $self->{mailto} = shift if @_;
    return $self->{mailto};
}

sub new {
    my ($class, %args) = @_;
    my @required_args = qw();
    PTDEBUG && print Dumper(%args);

    foreach my $arg (@required_args) {
        die "I need a $arg argument" unless $args{$arg};
    }

    my $self = {};
    bless $self, $class;

    # options should be used.
    $self->mailuser( $args{'mailuser'} );
    $self->mailpass( $args{'mailpass'} );
    $self->host( $args{'host'} );
    $self->helo( $args{'helo'} );
    $self->subject( $args{'subject'} || 'SQL audit messages' );
    $self->mailfrom( $args{'mailfrom'} || 'sql_audit@stat.com' );
    $self->mailto( $args{'mailto'} );

    return $self;
}

sub send {
    my ( $self ) = shift @_;
    undef $/;
    my $data = join("\n", map { $_ = '+-- ' . $_ } @_);
    my $to = join( ' ', @{$self->{mailto}});
    eval {
        `echo "$data" | /bin/mail -r "$self->{mailfrom}" -s "$self->{subject}" $to`;
    };

    if ( $@ ) {
       warn "error send: $@";
       return;
    }
    return 1;
}

sub send_smtp {
    my ( $self ) = shift @_;

    return unless @_;
    my $smtp;
    $smtp = Net::SMTP->new(
        Host  => $self->{host},
        Hello => $self->{helo},
        Debug => PTDEBUG ? 1 : 0,
    );

    unless ( defined $smtp ) {
        print "Cannot connect to $self->{host}\n";
        return;
    }

    my @data = join("\n", map { $_ = '+-- ' . $_ } @_);
    unshift @data, "Subject: $self->{subject}\n", "From: $self->{mailfrom}\n", 
                   "To:" . join("; ", @{$self->{mailto}}) . "\n\n";

    $smtp->auth( $self->{mailuser}, $self->{mailpass} );
    $smtp->mail( $self->{mailfrom} );
    $smtp->to( @{$self->{mailto}} );    
    $smtp->data(@data);
    $smtp->quit();
    return 1;
}

1;

# ##################################################################################
# Documentation.
# ##################################################################################

=pod

=head1 Name

    SQL::Audit::Email::Send -- Send message with system mail command or smtp method
                               with Net::SMTP

Note that Authen::SASL is needed by Net::SMTP.

=head1 SYNOPSIS

Example:

   my @mail = ('A@audit.com', 'B@audit.com');
   my $smtp = SQL::Audit::Email::Send->new(
      subject  => 'SQL audit message.',
      mailto   => \@mail,
      mailfrom => 'sql_audit@pwrd.com',
  );

  my @msg;
  push @msg, 'mail test';
  push @msg, 'warnings query.';
  $smtp->send( @msg ); 

  # send_smtp method need to be provide mailuser, mailpass, host, helo info.
  my $smtp = SQL::Audit::Email::Send->new(
      host     => 'mail.audit.com',
      helo     => 'mail.audit.com',
      mailuser => 'sendname',
      mailpass => 'sendpass',
      subject  => 'SQL audit message.',
      mailto   => \@mail,
      mailfrom => 'sql_audit@pwrd.com',
  );

  $smtp->send_smtp( @msg );

=head1 RISKS

Both send and send_smtp does not check whether it send ok or not. So, client can not recieve
message when mail command or mail server is not ok, attach file is not supported.

=head1 CONSTRUCTOR

=head2 new([ ARGS ]) 

Create a C<SQL::Audit::Email::Send>. mailuser, mailpass, host, helo can be set with hash format.

=over 4

=item mailuser

The user name that will be use send_smtp method, it's the sender username;

=item mailpass

The user password that use send_smtp method, it's the sender password;

=item host

The host name or ip address that mail server has.

=item helo

The helo info for sender to communicate with mail server, like telnet command with hello or hleo.

=item subject

The email subject message.

=item mailfrom

The sender email name reprent.

=item mailto

The email reciver, multi-email address can be set in array. see Examples.

=back

=head1 METHODS

=head2 send

Invoke system mail command as sender.

=head2 send_smtp

Need Net::SMTP to connect and authorized the sender info, and send message with this email address.

=head1 AUTHOR

zhe.chen <chenzhe07@gmail.com>

=head1 CHANGELOG

v0.1.0 initial version

=cut
