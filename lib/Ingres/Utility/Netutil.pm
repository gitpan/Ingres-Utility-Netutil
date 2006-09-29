package Ingres::Utility::Netutil;

use warnings;
use strict;
use Carp;
use Expect::Simple;
use Data::Dump qw(dump);

=head1 NAME

Ingres::Utility::Netutil - API to Netutil Ingres RDBMS utility


=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    use Ingres::Utility::Netutil;
    
    # create a connection to NETUTIL utility
    $foo = Ingres::Utility::Netutil->new();
    
    # Attention: many arguments accept wildcard *
    
    # showLogin($type,$vnode) - prepare to provide info on login VNodes
    #                           and return netutil ouput
    print $foo->showLogin('global','*');
    
    #
    # getLogin() - return one-by-one all login VNodes previously prepared
    while ( ($type, $login, $vnode, $acct) = $foo->getLogin() ) {
    	print "Type: $type\tName: $vnode\tAccount: $acct\n";
    }
    
    # showConn($type, $conn, $vnode, $addr, $proto, $listen)
    #                         - prepare to provide info on connections of a VNode
    #                           and return netutil ouput
    print $foo->showConn('global','sample_vnode_name', '*', '*', '*');
    
    #
    # getConn() - return one-by-one all connections of a VNodes previously prepared
    while ( @conn = $foo->getConn() ) {
	($type, $conn, $vnode, $addr, $proto, $listen) = @conn;
    	print "Type: $type\tName: $vnode\tAddress: $addr\tProtocol: $proto";
    	print "\tListen Address: $listenAddr\n";
    }
    
    # createLogin($type,$vnode,$acct, $passwd) - create a new VNode
    $foo->createLogin('global', 'new_vnode_name', 'sample_login_account', 'secret_passwd');
    
    # createConn($type,$vnode,$addr,$proto,$listenAddr) - create a connection for a VNode
    $foo->createConn('global', 'new_vnode_name', '192.168.0.1', 'tcp_ip', 'II');
    
    # destroyConn($type,$vnode,$acct, $passwd) - destroy a connection from a VNode
    $foo->destroyConn('global', 'new_vnode_name', '192.168.0.1', 'tcp_ip', 'II');
    
    # destroyLogin($type,$vnode) - destroy a VNode and all connections
    $foo->destroyLogin('global', 'new_vnode_name');
    
    # quiesceServer($serverId) - stop IIGCC server after all connections close (die gracefully)
    # if no $serverId is given, then all IIGCC servers are affected (carefull).
    $foo->quiesceServer('sample_server_id');
    
    # stopServer($serverId) - stop IIGCC server imediately (break connections)
    # if no $serverId is given, then all IIGCC servers are affected (carefull).
    $foo->stopServer('sample_server_id');

The server id can be obtained through L<Ingres::Utility::IINamu> module.
  
  
=head1 DESCRIPTION

This module provides an API to netutil utility for Ingres RDBMS,
which provides local control of IIGCC servers for Ingres Net
inbound and outbound remote connections, and also manage logins
and connections to remote servers, a.k.a. VNodes.


=head1 FUNCTIONS

=head2 new

Start interaction with netutil utility.

Takes the user id as optional argument to identify which user's
private VNodes to control. (user privileges may be necessary).

=cut

sub new {
	my $class = shift;
	my $this = {};
	$class = ref($class) || $class;
	bless $this, $class;
	my $userId = shift;
	if (! defined($ENV{'II_SYSTEM'})) {
		die $class . "::new(): Ingres environment variable II_SYSTEM not set";
	}
	my $Netutil_file = $ENV{'II_SYSTEM'} . '/ingres/bin/netutil';
	if ($userId) {
		$Netutil_file = $Netutil_file . " -u$userId";
	}
	
	
	if (! -x $Netutil_file) {
		die $class . "::new(): Ingres utility cannot be executed: $Netutil_file";
	}
	$this->{cmd} = $Netutil_file;
	$this->{xpct} = new Expect::Simple {
				Cmd => $Netutil_file,
#				Prompt => [ -re => 'Netutil>\s+' ],
#				DisconnectCmd => 'QUIT',
				Verbose => 0,
				Debug => 0,
				Timeout => 10
        } or die $this . "::new(): Module Expect::Simple cannot be instanciated";
        $this->{userId} = $userd;
	return $this;
}


=head2 showLogin

Prepare to return VNode login info.

Returns output from netutil.

Takes the VNode type to filter: GLOBAL/PRIVATE/*.

Takes de VNode name to filter (wildcard enabled).

=cut

sub showLogin {
	my $this = shift;
	my $type = uc (@_ ? shift : '*');
	if ($type) {
		if ($type != 'GLOBAL'  &&
		    $type != 'PRIVATE' &&
		    $type != '*') {
				die $this . "::showLogin(): invalid type: $type";
		}
	}
	my $vnode = uc (@_ ? shift : '*');
	my $obj = $this->{xpct};
	$this->{streamType} = 'LOGIN';
	$obj->send( "SHOW $type ". $this->{streamType} . " $vnode" );
	my $before = $obj->before;
	while ($before =~ /\ \ /) {
		$before =~ s/\ \ /\ /g;
	}
	$this->{stream}     = split(/\r\n/,$before);
	$this->{streamPtr}  = 0;
	$this->{streamType} = 'LOGIN';
	return $before;
}


=head2 getLogin

Returns sequentially (call-after-call) each VNode info reported by showLogin() as an array of
3 elements.

=cut

sub getLogin {
	my $this = shift;
	if ($this->{streamType} != 'LOGIN') {
		die $this . "::getLogin(): showLogin() must be previously invoked";
	}
	if (! $this->{stream}) {
		return ();
	}
	if (! $this->{streamPtr}) {
		$this->{streamPtr} = 0;
	}
	my @antes = split($/,$this->{stream});
	if ($#antes <= $this->{streamPtr}) {
		$this->{streamPtr} = 0;
		return ();
	}
	my $line = $antes[$this->{streamPtr}++];
	return split(/\ /, $line);
}


=head2 showConn

Prepare to return VNode connection info.

Returns output from netutil.

Takes the following parameters:
    $type    - VNode type: GLOBAL/PRIVATE/*
    $vnode   - VNode name or '*'
    $addr    - IP, hostname of the server or '*'
    $proto   - protocol name (tcp_ip, win_tcp, ipx, etc.)
    $listen  - remote server's listen address (generaly 'II') or '*'

=cut

sub showConn {
	my $this = shift;
	my $type = uc (@_ ? shift : '*');
	if ($type) {
		if ($type != 'GLOBAL'  &&
		    $type != 'PRIVATE' &&
		    $type != '*') {
				die $this . "::showConn(): invalid type: $type";
		}
	}
	my $vnode  = uc (@_ ? shift : '*');
	my $addr   = uc (@_ ? shift : '*');
	my $proto  = uc (@_ ? shift : '*');
	my $listen = uc (@_ ? shift : '*');
	my $obj = $this->{xpct};
	$this->{streamType} = 'CONNECTION';
	$obj->send( "SHOW $type " . $this->{streamType} . " $vnode $addr $proto $listen" );
	my $before = $obj->before;
	while ($before =~ /\ \ /) {
		$before =~ s/\ \ /\ /g;
	}
	$this->{stream}    = split(/\r\n/,$before);
	$this->{streamPtr} = 0;
	return $before;
}


=head2 getConn

Returns sequentially (call-after-call) each VNode connection info reported by showConn() as an array of
5 elements:

=cut

sub getConn {
	my $this = shift;
	if ($this->{streamType} != 'CONNECTION') {
		die $this . "::getConn(): showConn() must be previously invoked";
	}
	if (! $this->{stream}) {
		return ();
	}
	if (! $this->{streamPtr}) {
		$this->{streamPtr} = 0;
	}
	my @antes = split($/,$this->{stream});
	if ($#antes <= $this->{streamPtr}) {
		$this->{streamPtr} = 0;
		return ();
	}
	my $line = $antes[$this->{streamPtr}++];
	return split(/\ /, $line);
}


=head2 createLogin($type, $vnode)

Create a Login VNode.

Returns output from netutil.

Takes the following parameters:
    $type    - VNode type: GLOBAL/PRIVATE
    $vnode   - VNode name

=cut

sub createLogin {
	my $this = shift;
	my $type = uc (@_ ? shift : '*');
	if ($type != 'GLOBAL'  &&
	    $type != 'PRIVATE') {
			die $this . "::createLogin(): invalid type: $type";
	}
	if (! $vnode) {
		die $this . "::createLogin(): missing VNode name";
	}
	my $obj = $this->{xpct};
	$obj->send( "CREATE $type LOGIN $vnode" );
	my $before = $obj->before;
	while ($before =~ /\ \ /) {
		$before =~ s/\ \ /\ /g;
	}
	$this->{stream}     = '';	# no more getLogin()/getConn()
	$this->{streamPtr}  = 0;
	$this->{streamType} = '';
	return $before;
}


=head2 createConn

Create a connection for a Login VNode.

Returns output from netutil.

Takes the following parameters:
    $type    - VNode type: GLOBAL/PRIVATE
    $vnode   - VNode name
    $addr    - IP, hostname of the server
    $proto   - protocol name (tcp_ip, win_tcp, ipx, etc.)
    $listen  - remote server's listen address (generaly 'II')

=cut

sub createConn {
	my $this = shift;
	my $type, $vnode, $addr, $proto, $listen;
	($type, $vnode, $addr, $proto, $liste) = @_;
	$type = uc ($type);
	if ($type != 'GLOBAL'  &&
	    $type != 'PRIVATE') {
		die $this . "::createConn(): invalid type: $type";
	}
	my $param;
	foreach $param ('vnode', 'addr', 'proto', 'listen') {
		if (${$param} == '') {
			die $this . "::createConn():: missing parameter $param";
		}	
	}
	my $obj = $this->{xpct};
	$obj->send( "CREATE $type CONNECTION $vnode $addr $proto $listen" );
	my $before = $obj->before;
	while ($before =~ /\ \ /) {
		$before =~ s/\ \ /\ /g;
	}
	$this->{stream}     = '';	# no more getLogin()/getConn()
	$this->{streamPtr}  = 0;
	$this->{streamType} = '';
	return $before;
}


=head2 destroyLogin

Delete a Login VNode and all its connections.

Returns output from netutil.

Takes the VNode type to filter: GLOBAL/PRIVATE/*.

Takes de VNode name to filter (wildcard enabled).

=cut

sub destroyLogin {
	my $this = shift;
	my $type = uc (@_ ? shift : '*');
	if ($type) {
		if ($type != 'GLOBAL'  &&
		    $type != 'PRIVATE' &&
		    $type != '*') {
				die $this . "::destroyLogin(): invalid type: $type";
		}
	}
	my $vnode = uc (@_ ? shift : '*');
	my $obj = $this->{xpct};
	$this->{streamType} = 'LOGIN';
	$obj->send( "DESTROY $type ". $this->{streamType} . " $vnode" );
	my $before = $obj->before;
	while ($before =~ /\ \ /) {
		$before =~ s/\ \ /\ /g;
	}
	$this->{stream}     = '';	# no more getLogin()/getConn() 
	$this->{streamPtr}  = 0;
	$this->{streamType} = '';
	return $before;
}


=head2 destroyConn

Destroy (delete) a connection for a Login VNode.

Returns output from netutil.

Takes the following parameters:
    $type    - VNode type: GLOBAL/PRIVATE
    $vnode   - VNode name
    $addr    - IP, hostname of the server, or '*'
    $proto   - protocol name (tcp_ip, win_tcp, ipx, etc.), or '*'
    $listen  - remote server's listen address (generaly 'II'), or '*'

=cut

sub destroyConn {
	my $this = shift;
	my $type, $vnode, $addr, $proto, $listen;
	($type, $vnode, $addr, $proto, $liste) = @_;
	$type = uc ($type);
	if ($type != 'GLOBAL'  &&
	    $type != 'PRIVATE') {
		die $this . "::destroyConn(): invalid type: $type";
	}
	if ($vnode == ''  ||
	    $vnode == '*') {
		die $this . "::destroyConn(): invalid VNode name: $tvnode";
	}
	my $param;
	foreach $param ('addr', 'proto', 'listen') {
		if (${$param} == '') {
			${$param} = '*';
		}	
	}
	my $obj = $this->{xpct};
	$obj->send( "CREATE $type CONNECTION $vnode $addr $proto $listen" );
	my $before = $obj->before;
	while ($before =~ /\ \ /) {
		$before =~ s/\ \ /\ /g;
	}
	$this->{stream}     = '';	# no more getLogin()/getConn()
	$this->{streamPtr}  = 0;
	$this->{streamType} = '';
	return $before;
}




=for internal subroutine

sub quiesceStopServer {
	my $this = shift;
	my $cmd  = shift;
	my $obj  = $this->{xpct};
	$obj->send("$cmd $serverId");
	my $before = $obj->before;
	while ($before =~ /\ \ /) {
		$before =~ s/\ \ /\ /g;
	}
	return $before;
}

=head2 quiesceServer

Stops IIGCC server gracefully, i.e. after all connections are closed by clients.
No more connections are stablished.

Takes optional parameter serverId, to specify which server, or '*' for all servers.

=cut

sub quiesceServer {
	my $this = shift;
	my $serverId = @_ ? shift : '*';
	return quiesceStopServer('QUIESCE',$serverId);
}


=head2 stopServer

Stops IIGCC server immediatly, breaking all connections.

Takes optional parameter serverId, to specify which server, or '*' for all servers.

=cut

sub stopServer {
	my $this = shift;
	my $serverId = @_ ? shift : '*';
	return quiesceStopServer('STOP',$serverId);
}


=head1 DIAGNOSTICS

=over

=item C<< Ingres environment variable II_SYSTEM not set >>

Ingres environment variables should be set in the user session running
this module.
II_SYSTEM provides the root install dir (the one before 'ingres' dir).
LD_LIBRARY_PATH too. See Ingres RDBMS docs.

=item C<< Ingres utility cannot be executed: _COMMAND_FULL_PATH_ >>

The Netutil command could not be found or does not permits execution for
the current user.

=item C<< invalid type: _VNODE_TYPE_ >>

Call to a VNode related method should be given a valid VNode type (GLOBAL/PRIVATE),
or a wildcard (*), when permitted.

=item C<< showLogin() must be previously invoked >>

A method call should be preceded by a preparatory call to showLogin().
If any call is made to createXxx() or deleteXxx(), (whichever Login or Conn), then showLogin()
should be called again.

=item C<< showConn() must be previously invoked >>

A method call should be preceded by a preparatory call to showConn().
If any call is made to createXxx() or deleteXxx(), (whichever Login or Conn), then showConn()
should be called again.

=item C<< missing VNode name >>

VNode name identifying a Login is required for this method.

=item C<< missing parameter _PARAMETER_ >>

The method requires the mentioned parameter to perform an action.

=back


=head1 CONFIGURATION AND ENVIRONMENT
  
Requires Ingres environment variables, such as II_SYSTEM and LD_LIBRARY_PATH.

See Ingres RDBMS documentation.


=head1 DEPENDENCIES

L<Expect::Simple>


=head1 INCOMPATIBILITIES

None reported.


=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests to C<bug-ingres-utility-Netutil at rt.cpan.org>,
or through the web interface at L<http://rt.cpan.org>.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Ingres::Utility::Netutil

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Ingres-Utility-Netutil>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Ingres-Utility-Netutil>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Ingres-Utility-Netutil>

=item * Search CPAN

L<http://search.cpan.org/dist/Ingres-Utility-Netutil>

=back


=head1 ACKNOWLEDGEMENTS

Thanks to Computer Associates (CA) for licensing Ingres as
open source, and let us hope for Ingres Corp to keep it that way.

=head1 AUTHOR

Joner Cyrre Worm  C<< <FAJCNLXLLXIH at spammotel.com> >>


=head1 LICENSE AND COPYRIGHT

Copyright (c) 2006, Joner Cyrre Worm C<< <FAJCNLXLLXIH at spammotel.com> >>. All rights reserved.


Ingres is a registered brand of Ingres Corporation.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

=cut

1; # End of Ingres::Utility::Netutil
__END__
