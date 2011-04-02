package POE::Component::IRC::Plugin::Karma;

# ABSTRACT: A POE::Component::IRC plugin that keeps track of karma

use Moose;
use DBI;
use DBD::SQLite;
use POE::Component::IRC::Plugin qw( PCI_EAT_NONE );
use POE::Component::IRC::Common qw( parse_user );

# TODO split the datastore stuff into pocoirc-plugin-datastore
# so it can be used by other plugins that need to store data
# then we can code plugin-seen and plugin-awaymsg stuff and have it use the datastore
# make it as braindead ez to use as the bot-basicbot system of saving data :)
# Getty wants me to have it use dbic which would make it even more awesome...

# TODO do we need a help system? "bot: karma" should return whatever...

# TODO do we need a botsnack thingy? bot++ bot--
# seen in bot-basicbot-karma where a user tries to karma the bot itself and it replies with something

=attr addressed

If this is a true value, the karma commands has to be sent to the bot.

	# addressed = true
	<you> bot: perl++

	# addressed = false
	<you> perl++

The default is: false

=cut

has 'addressed' => (
	is	=> 'rw',
	isa	=> 'Bool',
	default	=> 0,
);

=attr privmsg

If this is a true value, all karma replies will be sent to the user in a privmsg.

The default is: false

=cut

has 'privmsg' => (
	is	=> 'rw',
	isa	=> 'Bool',
	default	=> 0,
);

=attr selfkarma

If this is a true value, users are allowed to karma themselves.

The default is: false

=cut

has 'selfkarma' => (
	is	=> 'rw',
	isa	=> 'Bool',
	default	=> 0,
);

=attr replykarma

If this is a true value, this bot will reply to all karma additions with the current score.

The default is: false

=cut

has 'replykarma' => (
	is	=> 'rw',
	isa	=> 'Bool',
	default	=> 0,
);

=attr extrastats

If this is a true value, this bot will display extra stats about the karma on reply.

The default is: false

=cut

has 'extrastats' => (
	is	=> 'rw',
	isa	=> 'Bool',
	default	=> 0,
);

=attr sqlite

Set the path to the SQLite database which will hold the karma stats.

BEWARE: In the future this might be changed to a more "fancy" system!

The default is: karma_stats.db

=cut

has 'sqlite' => (
	is	=> 'ro',
	isa	=> 'Str',
	default	=> 'karma_stats.db',
);

sub PCI_register {
	my ( $self, $irc ) = @_;

	$irc->plugin_register( $self, 'SERVER', qw( public msg ctcp_action ) );

	# setup the db
	$self->_setup_dbi( $self->_get_dbi );

	return 1;
}

sub PCI_unregister {
	my ( $self, $irc ) = @_;

	return 1;
}

sub S_ctcp_action {
	my ( $self, $irc ) = splice @_, 0 , 2;
	my ( $nick, $user, $host ) = parse_user( ${ $_[0] } );
	my $channel = ${ $_[1] }->[0];
	my $msg = ${ $_[2] };

	my $reply = $self->_karma(
		nick	=> $nick,
		user	=> $user,
		host	=> $host,
		where	=> $channel,
		str	=> ${ $_[2] },
	);

	if ( defined $reply ) {
		$irc->yield( 'privmsg', $channel, $nick . ': ' . $reply );
	}

	return PCI_EAT_NONE;
}

sub S_public {
	my ( $self, $irc ) = splice @_, 0 , 2;
	my ( $nick, $user, $host ) = parse_user( ${ $_[0] } );
	my $channel = ${ $_[1] }->[0];
	my $msg = ${ $_[2] };
	my $string;

	# check addressed mode first
	my $mynick = $irc->nick_name();
	($string) = $msg =~ m/^\s*\Q$mynick\E[\:\,\;\.]?\s*(.*)$/i;
	if ( ! defined $string and ! $self->addressed ) {
		$string = $msg;
	}

	if ( defined $string ) {
		my $reply = $self->_karma(
			nick	=> $nick,
			user	=> $user,
			host	=> $host,
			where	=> $channel,
			str	=> $string,
		);

		if ( defined $reply ) {
			if ( $self->privmsg ) {
				$irc->yield( 'privmsg', $nick, $reply );
			} else {
				$irc->yield( 'privmsg', $channel, $nick . ': ' . $reply );
			}
		}
	}

	return PCI_EAT_NONE;
}

sub S_msg {
	my ( $self, $irc ) = splice @_, 0 , 2;
	my ( $nick, $user, $host ) = parse_user( ${ $_[0] } );

	my $reply = $self->_karma(
		nick	=> $nick,
		user	=> $user,
		host	=> $host,
		where	=> 'privmsg',
		str	=> ${ $_[2] },
	);

	if ( defined $reply ) {
		$irc->yield( 'privmsg', $nick, $reply );
	}

	return PCI_EAT_NONE;
}

sub _karma {
	my( $self, %args ) = @_;

	# many different ways to get karma...
	if ( $args{'str'} =~ /^\s*karma\s*(.+)$/i ) {
		# return the karma of the requested string
		return $self->_get_karma( $1 );

	# TODO are those worth it to implement?
#	} elsif ( $args{'str'} =~ /^\s*karmahigh\s*$/i ) {
#		# return the list of highest karma'd words
#		return $self->_get_karmahigh;
#	} elsif ( $args{'str'} =~ /^\s*karmalow\s*$/i ) {
#		# return the list of lowest karma'd words
#		return $self->_get_karmalow;
#	} elsif ( $args{'str'} =~ /^\s*karmalast\s*(.+)$/ ) {
#		# returns the list of last karma contributors
#		my $karma = $1;
#
#		# clean the karma
#		$karma =~ s/^\s+//;
#		$karma =~ s/\s+$//;
#
#		return $self->_get_karmalast( $karma );

	# TODO parse multi-karma in one string
	# <you> hey this++ is super awesome++ # rockin!
	} elsif ( $args{'str'} =~ /\(([^\)]+)\)(\+\+|--)\s*(\#.+)?/ or $args{'str'} =~ /(\w+)(\+\+|--)\s*(\#.+)?/ ) {
		# karma'd something ( with a comment? )
		my( $karma, $op, $comment ) = ( $1, $2, $3 );

		# clean the karma
		$karma =~ s/^\s+//;
		$karma =~ s/\s+$//;

		# Is it a selfkarma?
		if ( ! $self->selfkarma and lc( $karma ) eq lc( $args{'nick'} ) ) {
			return;
		} else {
			# clean the comment
			$comment =~ s/^\s*\#\s*// if defined $comment;

			$self->_add_karma(
				karma	=> $karma,
				op	=> $op,
				comment	=> $comment,
				%args,
			);

			if ( $self->replykarma ) {
				return $self->_get_karma( $karma );
			}
		}
	} else {
		# not a karma command
	}

	return;
}

sub _get_karma {
	my( $self, $karma ) = @_;

	# Get the score from the DB
	my $dbh = $self->_get_dbi;
	my $sth = $dbh->prepare_cached( 'SELECT mode, count(mode) AS count FROM karma WHERE karma = ? GROUP BY mode' ) or die $dbh->errstr;
	$sth->execute( $karma ) or die $sth->errstr;
	my( $up, $down ) = ( 0, 0 );
	while ( my $row = $sth->fetchrow_arrayref ) {
		if ( $row->[0] == 1 ) {
			$up = $row->[1];
		} else {
			$down = $row->[1];
		}
	}
	$sth->finish;

	my $score = $up - $down;
	$score = undef if ( $up == 0 and $down == 0 );

	my $result;
	if ( ! defined $score ) {
		$result = "'$karma' has no karma";
	} else {
		if ( $score == 0 ) {
			$result = "'$karma' has neutral karma";
			if ( $self->extrastats ) {
				my $total = $up + $down;
				$result .= " [ $total votes ]";
			}
		} else {
			$result = "'$karma' has karma of $score";
			if ( $self->extrastats ) {
				if ( $up and $down ) {
					$result .= " [ $up ++ and $down -- votes ]";
				} elsif ( $up ) {
					$result .= " [ $up ++ votes ]";
				} else {
					$result .= " [ $down -- votes ]";
				}
			}
		}
	}

	return $result;
}

sub _add_karma {
	my( $self, %args ) = @_;

	# munge the nick back into original format
	$args{'who'} = $args{'nick'} . '!' . $args{'user'} . '@' . $args{'host'};

	# insert it into the DB!
	my $dbh = $self->_get_dbi;
	my $sth = $dbh->prepare_cached( 'INSERT INTO karma ( who, "where", timestamp, karma, mode, comment, said ) VALUES ( ?, ?, ?, ?, ?, ?, ? )' );
	$sth->execute(
		$args{'who'},
		$args{'where'},
		scalar time,
		$args{'karma'},
		( $args{'op'} eq '++' ? 1 : 0 ),
		$args{'comment'},
		$args{'str'},
	) or die $dbh->errstr;
	$sth->finish;

	return;
}

sub _get_dbi {
	my $self = shift;

	my $dbh = DBI->connect_cached( "dbi:SQLite:dbname=" . $self->sqlite, '', '' );

	# set some SQLite tweaks
	$dbh->do( 'PRAGMA synchronous = OFF' ) or die $dbh->errstr;

	return $dbh;
}

sub _setup_dbi {
	my( $self, $dbh ) = @_;

	# TODO <dngor> Apocalypse: You can select mode, count(mode) from karma group by mode ... it'll return a ++ and -- count, which you'll have to add yourself for the overall score.

	# create the table itself
	$dbh->do( 'CREATE TABLE IF NOT EXISTS karma ( ' .
		'who TEXT NOT NULL, ' .			# who made the karma
		'"where" TEXT NOT NULL, ' .		# privmsg or in chan
		'timestamp INTEGER NOT NULL, ' .	# timestamp of karma
		'karma TEXT NOT NULL, ' .		# the stuff being karma'd
		'mode BOOL, ' .				# 1 if it was a ++, 0 if it was a --
		'comment TEXT, ' .			# the comment given with the karma ( optional )
		'said TEXT NOT NULL ' .			# the full text the user said
	')' ) or die $dbh->errstr;

	# create the indexes to speed up searching
	$dbh->do( 'CREATE INDEX IF NOT EXISTS karma_karma ON karma ( karma )' ) or die $dbh->errstr;
	$dbh->do( 'CREATE INDEX IF NOT EXISTS karma_mode ON karma ( mode )' ) or die $dbh->errstr;

	return;
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;

=pod

=for Pod::Coverage PCI_register PCI_unregister S_msg S_public S_ctcp_action

=head1 SYNOPSIS

	# A simple bot to showcase karma capabilities
	use strict; use warnings;

	use POE qw( Component::IRC Component::IRC::Plugin::Karma Component::IRC::Plugin::AutoJoin );

	# Create a new PoCo-IRC object
	my $irc = POE::Component::IRC->spawn(
		nick => 'karmabot',
		ircname => 'karmabot',
		server  => 'localhost',
	) or die "Oh noooo! $!";

	# Setup our plugins + tell the bot to connect!
	$irc->plugin_add( 'AutoJoin', POE::Component::IRC::Plugin::AutoJoin->new( Channels => [ '#test' ] ));
	$irc->plugin_add( 'Karma', POE::Component::IRC::Plugin::Karma->new );
	$irc->yield( connect => { } );

	POE::Kernel->run;

=head1 DESCRIPTION

This plugin keeps track of karma ( perl++ or perl-- ) said on IRC and provides an interface to retrieve statistics.

The bot will watch for karma in channel messages, privmsgs and ctcp actions.

=head2 IRC USAGE

=for :list
* <thing>++ # <comment>
Increases the karma for <thing> ( with optional comment )
* <thing>-- # <comment>
Decreases the karma for <thing> ( with optional comment )
* karma <thing>
Replies with the karma rating for <thing>

=head1 SEE ALSO
POE::Component::IRC
Bot::BasicBot::Pluggable::Module::Karma

=cut
