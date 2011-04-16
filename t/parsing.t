#!/usr/bin/perl

use POE::Component::IRC::Plugin::Karma;
use Test::MockObject::Extends;
use Test::More;

# Okay, build up the list of testcases for our parsing engine
my %tests = (
	# string to test against => arrayref
	#	arrayref holds hashrefs of results
	#		k => the karma string
	#		m => the mode ( ++ or -- )
	#		c => the comment
	#		TODO => 1, if present, treat this as TODO
	'foo++' => [
		{
			'k' => 'foo',
			'm' => '++',
			'c' => undef,
		},
	],
	'(a foo)++' => [
		{
			'k' => 'a foo',
			'm' => '++',
			'c' => undef,
		},
	],
	'(    a foo  )++' => [
		{
			'k' => 'a foo',
			'm' => '++',
			'c' => undef,
		},
	],
	'(a foo)++ # nice!' => [
		{
			'k' => 'a foo',
			'm' => '++',
			'c' => 'nice!',
		},
	],
	'this foo++ is nice' => [
		{
			'k' => 'foo',
			'm' => '++',
			'c' => undef,
		},
	],
	'this foo++ is nice++ to know' => [
		{
			'k' => 'foo',
			'm' => '++',
			'c' => undef,
		},
		{
			'k' => 'nice',
			'm' => '++',
			'c' => undef,
		},
	],
	'this foo++ is nice++ to know++ # haha' => [
		{
			'k' => 'foo',
			'm' => '++',
			'c' => undef,
		},
		{
			'k' => 'nice',
			'm' => '++',
			'c' => undef,
		},
		{
			'k' => 'know',
			'm' => '++',
			'c' => 'haha',
		},
	],
	'(this foo)++ is nice++ to know++ # haha' => [
		{
			'k' => 'this foo',
			'm' => '++',
			'c' => undef,
		},
		{
			'k' => 'nice',
			'm' => '++',
			'c' => undef,
		},
		{
			'k' => 'know',
			'm' => '++',
			'c' => 'haha',
		},
	],
	'(this foo)++ is nice++ (to know)++ # haha' => [
		{
			'k' => 'this foo',
			'm' => '++',
			'c' => undef,
		},
		{
			'k' => 'nice',
			'm' => '++',
			'c' => undef,
		},
		{
			'k' => 'to know',
			'm' => '++',
			'c' => 'haha',
		},
	],
	'this foo++ # super! i like++ this' => [
		{
			'k' => 'foo',
			'm' => '++',
			'c' => 'super! i like++ this',
		},
	],
	'(a foo)++ hi # c' => [
		{
			'k' => 'a foo',
			'm' => '++',
			'c' => undef,
		},
	],
	'foo++ hey # c' => [
		{
			'k' => 'foo',
			'm' => '++',
			'c' => undef,
		},
	],
	'hey foo++ (thi sis)++ # awesome super++ (thing and)++ # nice' => [
		{
			'k' => 'foo',
			'm' => '++',
			'c' => undef,
		},
		{
			'k' => 'thi sis',
			'm' => '++',
			'c' => 'awesome super++ (thing and)++ # nice',
		},
	],
	'foo++ (super cool)++ # nice i like++ this awesome++ # stuff' => [
		{
			'k' => 'foo',
			'm' => '++',
			'c' => undef,
		},
		{
			'k' => 'super cool',
			'm' => '++',
			'c' => 'nice i like++ this awesome++ # stuff',
		},
	],

	# those may be "incorrect" at first glance but it actually is the right behavior
	# as the comment is not for a karma, so we are "allowed" to parse it for the karma words
	# in it, and this makes things a bit more complicated
	'foo++ this # awesome comment++' => [
		{
			'k' => 'foo',
			'm' => '++',
			'c' => undef,
		},
		{
			'k' => 'comment',
			'm' => '++',
			'c' => undef,
		},
	],
	'(a foo)++ this # comment++' => [
		{
			'k' => 'a foo',
			'm' => '++',
			'c' => undef,
		},
		{
			'k' => 'comment',
			'm' => '++',
			'c' => undef,
		},
	],
	'foo++ this # awesome comment++ # hey' => [
		{
			'k' => 'foo',
			'm' => '++',
			'c' => undef,
		},
		{
			'k' => 'comment',
			'm' => '++',
			'c' => 'hey',
		},
	],
	'(a foo)++ this # comment++ # hola' => [
		{
			'k' => 'a foo',
			'm' => '++',
			'c' => undef,
		},
		{
			'k' => 'comment',
			'm' => '++',
			'c' => 'hola',
		},
	],
	'(a foo)++ this # comment++ # hola this++ should not work++ # another comment++' => [
		{
			'k' => 'a foo',
			'm' => '++',
			'c' => undef,
		},
		{
			'k' => 'comment',
			'm' => '++',
			'c' => 'hola this++ should not work++ # another comment++',
		},
	],

	# Oh, a certain idiot just got a nice 60" tv and wants to brag... ;)
	'60"++' => [
		{
			'k' => '60"',
			'm' => '++',
			'c' => undef,
		},
	],
);

# Count the number of tests we have
# one test to compare number of matches
# 3 tests per match to compare k/m/c
my $num_tests = 0;

# This is dirty, but we build the reverse testcase ( with -- )
foreach my $t ( keys %tests ) {
	my $reverse = $t;
	$reverse =~ s/\+\+/\-\-/g;
	$num_tests += 2;
	foreach my $match ( @{ $tests{ $t } } ) {
		my $rev_c = $match->{'c'};
		$rev_c =~ s/\+\+/\-\-/g if defined $rev_c;
		push( @{ $tests{ $reverse } }, {
			'k' => $match->{'k'},
			'm' => '--',
			'c' => $rev_c,
			( exists $match->{'TODO'} ? ( 'TODO' => 1 ) : () ),
		} );

		$num_tests += 6;
	}
}

# Start the actual testing!
plan tests => $num_tests;
my @results;
my $karma = POE::Component::IRC::Plugin::Karma->new;
$karma = Test::MockObject::Extends->new( $karma );
$karma->mock( '_add_karma', sub {
	my ( $self, %args ) = @_;
	push( @results, \%args );
	return;
} );

# call the parser and analyze the data
foreach my $t ( keys %tests ) {
	$karma->_karma(
		nick	=> 'tester',
		user	=> 'tester',
		host	=> 'localhost',
		where	=> '#test',
		str	=> $t,
	);

	# compare it!
	if ( exists $tests{ $t }[0]{'TODO'} ) {
		TODO: {
			local $TODO = "This part of the parser engine is still a todo";
			compare_results( $t );
		}
	} else {
		compare_results( $t );
	}

	# clear the results for the next run
	@results = ();
}

sub compare_results {
	my $t = shift;

	# see if we have the same number of matches
	cmp_ok( scalar @results, '==', scalar @{ $tests{ $t } }, 'parsed karma count for ' . $t );

	# Compare each match
	for ( my $i = 0; $i < scalar @{ $tests{ $t } }; $i++ ) {
		cmp_ok( $results[$i]->{'karma'}, 'eq', $tests{ $t }[$i]{'k'}, 'karma matches' );
		cmp_ok( $results[$i]->{'op'}, 'eq', $tests{ $t }[$i]{'m'}, 'mode matches' );

		# comment can be undef...
		if ( ! defined $tests{ $t }[$i]{'c'} ) {
			ok( ! defined $results[$i]->{'comment'}, 'comment matches' );
		} else {
			cmp_ok( $results[$i]->{'comment'}, 'eq', $tests{ $t }[$i]{'c'}, 'comment matches' );
		}
	}
}

