package POE::Component::IRC::Plugin::Karma;

# ABSTRACT: A POE::Component::IRC plugin that keeps track of karma

use Any::Moose;
use DBI;
use DBD::SQLite;
use POE::Component::IRC::Plugin qw( PCI_EAT_NONE );
use POE::Component::IRC::Common qw( parse_user );
use Text::Karma;

# TODO do we need a help system? "bot: karma" should return whatever...

# TODO do we need a botsnack thingy? bot++ bot--
# seen in bot-basicbot-karma where a user tries to karma the bot itself and it replies with something

# TODO do we need a warn_selfkarma option so it warns the user trying to karma themselves?

# TODO
#<Getty> explain duckduckgo
#<Getty> explain karma duckduckgo
#<Getty> ah not implemented, ok

=attr addressed

If this is a true value, the karma-affecting text has to be sent to the bot.

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

=attr casesens

If this is a true value, karma checking will be done in a case-sensitive way.

The default is: false

=cut

has 'casesens' => (
	is	=> 'rw',
	isa	=> 'Bool',
	default	=> 0,
);

=attr privmsg

If this is a true value, all karma replies will be sent to the user in private.

The default is: false

=cut

has 'privmsg' => (
	is	=> 'rw',
	isa	=> 'Bool',
	default	=> 0,
);

=attr replymethod

The method of reply. Can be 'notice' (default) or 'privmsg'.

=cut

has 'replymethod' => (
	is	=> 'rw',
	isa	=> 'Str',
	default => 'notice',
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

From the L<DBD::SQLite> docs: Although the database is stored in a single file, the directory containing the
database file must be writable by SQLite because the library will create several temporary files there.

The default is: karma_stats.db

BEWARE: In the future this might be changed to a more "fancy" system!

=cut

has 'sqlite' => (
	is	=> 'ro',
	isa	=> 'Str',
	default	=> 'karma_stats.db',
);

has '_karma' => (
	is	=> 'rw',
	isa	=> 'Text::Karma',
);

sub PCI_register {
	my ( $self, $irc ) = @_;

	my $botcmd;
	if (!(($botcmd) = grep { $_->isa('POE::Component::IRC::Plugin::BotCommand') } values %{ $irc->plugin_list() })) {
		die __PACKAGE__ . " requires an active BotCommand plugin\n";
	}
	$botcmd->add(karma => 'Usage: karma <subject>');
	$irc->plugin_register($self, 'SERVER', qw(public msg ctcp_action botcmd_karma));

	# setup the db
	$self->_karma(Text::Karma->new(dbh => $self->_get_dbi));

	return 1;
}

sub PCI_unregister {
	my ( $self, $irc ) = @_;

	return 1;
}

sub S_botcmd_karma {
	my ($self, $irc)  = splice @_, 0, 2;
	my $nick    = parse_user( ${ $_[0] } );
	my $chan    = ${ $_[1] };
	my $subject = ${ $_[2] };

	if (!defined $subject) {
		$irc->yield($self->replymethod, $chan, "$nick: No subject supplied!");
	}
	else {
		my $karma = $self->_karma->get_karma(
			subject => $subject,
			case_sens => $self->casesens,
		);
		$irc->yield($self->replymethod, $chan, "$nick: ".$self->_get_karma($subject));
	}
	return PCI_EAT_NONE;
}

sub S_ctcp_action {
	my ( $self, $irc ) = splice @_, 0 , 2;
	my $who = ${ $_[0] };
	my $nick = parse_user($who);
	my $channel = ${ $_[1] }->[0];
	my $msg = ${ $_[2] };

	my $replies = $self->_handle_karma(
		nick	=> $nick,
		who	=> $who,
		where	=> $channel,
		str	=> $msg,
	);

	if ( defined $replies ) {
		$irc->yield($self->replymethod, $channel, $nick . ': ' . $_ ) for @$replies;
	}

	return PCI_EAT_NONE;
}

sub S_public {
	my ( $self, $irc ) = splice @_, 0 , 2;
	my $who = ${ $_[0] };
	my $nick = parse_user($who);
	my $channel = ${ $_[1] }->[0];
	my $msg = ${ $_[2] };
	my $string;

	# check addressed mode first
	my $mynick = $irc->nick_name();
	($string) = $msg =~ m/^\s*\Q$mynick\E[\:\,\;\.]?\s*(.*)$/i;
	if ( ! defined $string and ! $self->addressed ) {
		$string = $msg;
	}

	return PCI_EAT_NONE if !defined $string;
	my $replies = $self->_handle_karma(
		nick	=> $nick,
		who	=> $who,
		where	=> $channel,
		str	=> $string,
	);

	if ($replies) {
		foreach my $r ( @$replies ) {
			if ( $self->privmsg ) {
				$irc->yield($self->replymethod, $nick, $r );
			} else {
				$irc->yield($self->replymethod, $channel, $nick . ': ' . $r );
			}
		}
	}

	return PCI_EAT_NONE;
}

sub S_msg {
	my ( $self, $irc ) = splice @_, 0 , 2;
	my $who = ${ $_[0] };
	my $nick = parse_user($who);
	my $msg = ${ $_[2] };

	my $replies = $self->_handle_karma(
		nick	=> $nick,
		where	=> 'privmsg',
		str	=> $msg,
	);

	if ( defined $replies ) {
		$irc->yield($self->replymethod, $nick, $_ ) for @$replies;
	}

	return PCI_EAT_NONE;
}

sub _handle_karma {
	my ($self, %args) = @_;

	my @replies;

	# TODO are those worth it to implement?
#	} elsif ( $args{'str'} =~ /^\s*karmahigh\s*$/i ) {
#		# return the list of highest karma'd words
#		return [ $self->_get_karmahigh ];
#	} elsif ( $args{'str'} =~ /^\s*karmalow\s*$/i ) {
#		# return the list of lowest karma'd words
#		return [ $self->_get_karmalow ];
#	} elsif ( $args{'str'} =~ /^\s*karmalast\s*(.+)$/ ) {
#		# returns the list of last karma contributors
#		my $karma = $1;
#
#		# clean the karma
#		$karma =~ s/^\s+//;
#		$karma =~ s/\s+$//;
#
#		return [ $self->_get_karmalast( $karma ) ];

	# many different ways to get karma...
	my $karmas = $self->_karma->process_karma(
		nick		=> $args{nick},
		who		=> $args{who},
		where		=> $args{where},
		str		=> $args{str},
		self_karma	=> $self->selfkarma,
	);
	if ($self->replykarma) {
		my %subjects;
		$subjects{ $_->{subject} } = 1 for @$karmas;
		push @replies, $self->_get_karma($_) for keys %subjects;
	}

	return \@replies;
}

sub _get_karma {
	my( $self, $subject ) = @_;

	my $karma = $self->_karma->get_karma(
	    subject => $subject,
	    case_sens => $self->casesens,
	);

	my $result;
	if ( ! defined $karma ) {
		$result = "'$subject' has no karma";
	} else {
		if ( $karma->{score} == 0 ) {
			$result = "'$subject' has neutral karma";
			if ( $self->extrastats ) {
				my $total = $karma->{up} + $karma->{down};
				$result .= " [ $total votes ]";
			}
		} else {
			$result = "'$subject' has karma of $karma->{score}";
			if ( $self->extrastats ) {
				if ( $karma->{up} and $karma->{down} ) {
					$result .= " [ $karma->{up} ++ and $karma->{down} -- votes ]";
				} elsif ( $karma->{up} ) {
					$result .= " [ $karma->{up} ++ votes ]";
				} else {
					$result .= " [ $karma->{down} -- votes ]";
				}
			}
		}
	}

	return $result;
}

sub _get_dbi {
	my $self = shift;

	my $dbh = DBI->connect_cached( "dbi:SQLite:dbname=" . $self->sqlite, '', '' );

	# set some SQLite tweaks
	$dbh->do( 'PRAGMA synchronous = OFF' ) or die $dbh->errstr;
	$dbh->do( 'PRAGMA locking_mode = EXCLUSIVE' ) or die $dbh->errstr;

	return $dbh;
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;

=pod

=for stopwords karma

=for Pod::Coverage PCI_register PCI_unregister S_msg S_public S_ctcp_action

=head1 SYNOPSIS

To quickly get an IRC bot with this plugin up and running, you can use
L<App::Pocoirc|App::Pocoirc>:

 $ pocoirc -s irc.perl.org -j '#bots' -a BotCommand -a Karma

Or use it in your code:
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
	$irc->plugin_add( 'Karma', POE::Component::IRC::Plugin::Karma->new( extrastats => 1 ) );
	$irc->yield( connect => { } );

	POE::Kernel->run;

=head1 DESCRIPTION

This plugin keeps track of karma ( perl++ or perl-- ) said on IRC and provides an interface to retrieve statistics.

The bot will watch for karma in channel messages, privmsgs and ctcp actions.

=head2 IRC USAGE

=for :list
* thing++ # comment
Increases the karma for <thing> ( with optional comment )
* thing-- # comment
Decreases the karma for <thing> ( with optional comment )
* (a thing with spaces)++ # comment
Increases the karma for <a thing with spaces> ( with optional comment )
* karma thing
Replies with the karma rating for <thing>
* karma ( a thing with spaces )
Replies with the karma rating for <a thing with spaces>

=head1 SEE ALSO
POE::Component::IRC
Bot::BasicBot::Pluggable::Module::Karma

=cut
