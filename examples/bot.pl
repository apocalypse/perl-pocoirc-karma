# A simple bot to showcase karma capabilities
use strict; use warnings;

use POE qw( Component::IRC Component::IRC::Plugin::Karma Component::IRC::Plugin::AutoJoin Component::IRC::Plugin::Connector );

my $nickname = 'Flibble' . $$;
my $ircname  = 'Flibble the Sailor Bot';
my $server   = '192.168.0.200';

my @channels = ('#test');

POE::Session->create(
	package_states => [
		main => [ qw( _default _start _child ) ],
	],
);

$poe_kernel->run();

sub _start {
	my $heap = $_[HEAP];

	# We create a new PoCo-IRC object
	my $irc = POE::Component::IRC->spawn(
		nick => $nickname,
		ircname => $ircname,
		server  => $server,
	) or die "Oh noooo! $!";

	# store the irc object
	$heap->{irc} = $irc;

	# Setup our plugins
	$irc->plugin_add( 'AutoJoin', POE::Component::IRC::Plugin::AutoJoin->new( Channels => \@channels ));
	$irc->plugin_add( 'Connector', POE::Component::IRC::Plugin::Connector->new );
	$irc->plugin_add( 'Karma', POE::Component::IRC::Plugin::Karma->new( extrastats => 1 ) );

	$irc->yield( register => 'all' );
	$irc->yield( connect => { } );
	return;
}

sub _child {
	return;
}

# We registered for all events, this will produce some debug info.
sub _default {
	my ($event, $args) = @_[ARG0 .. $#_];
	my @output = ( "$event: " );

	for my $arg (@$args) {
		if ( ref $arg eq 'ARRAY' ) {
			push( @output, '[' . join(', ', @$arg ) . ']' );
		} else {
			push ( @output, "'$arg'" );
		}
	}
	print join ' ', @output, "\n";
	return;
}
