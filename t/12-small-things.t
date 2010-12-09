#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Data::Dumper;

use CouchDB::Client             qw();
use CouchDB::Client::DB         qw();
use CouchDB::Client::Doc        qw();
use CouchDB::Client::DesignDoc  qw();

use JSON::Any;
use LWP::UserAgent;

my $cdb = CouchDB::Client->new( uri => $ENV{COUCHDB_CLIENT_URI} || 'http://localhost:5984/' );
if($cdb->testConnection) {
	plan tests => 22;
}
else {
	plan skip_all => 'Could not connect to CouchDB, skipping.';
	warn <<EOMSG;
You can specify how these tests can connect to CouchDB by setting the 
COUCHDB_CLIENT_URI environment variable to the address of your server.
EOMSG
	exit;
}

my $C = $cdb;
my $DB = $C->newDB('blah');

### LOW LEVEL FUNCTIONS
{
	my %encoded = $DB->fixViewArgs(
		startkey => 42,
		endkey   => 'foo',
		descending => 1,
		update => 1,
		keeps => 'me correctly',
		group => 1,
	);

	is_deeply(\%encoded, {
		startkey => '42',
		endkey => '"foo"',
		descending => 'true',
		keeps => 'me correctly',
		group => 'true',
	}, "fixViewArgs works as expected");

	%encoded = $DB->fixViewArgs(descending => 0, update => 0);
	is_deeply(\%encoded, { update => 'false' }, "fixViewArgs works as expected 2");

	%encoded = $DB->fixViewArgs(
		key      => [ 'one',   'two'   ],
		startkey => { 'key' => 'value' },
	);

	# I've made the regexps as forgiving as a I can to account for possible
	# differences in the various json encoders.
	ok($encoded{key} =~ /^\s*\[\s*['"]one['"]\s*,\s*['"]two['"]\s*\]\s*$/,      "Array encode works");
	ok($encoded{startkey} =~ /^\s*\{['"]?key['"]?\s*:\s*['"]value['"]\s*}\s*$/, "Hash encode works");

}

# test _is_currently_numeric
{
	# bare number not assigned to a scalar
	is($DB->_is_currently_numeric(10),1,"bare number is numeric");

	# bare string
	is($DB->_is_currently_numeric("string"),0,"bare string is not numeric");

	my $int = 12;
	is($DB->_is_currently_numeric($int),1,"int scalar is numeric");

	$int = ''.$int;
	is($DB->_is_currently_numeric($int),0,"int is not numeric after string concatination");

	# interesting gotcha.  ++ for some reason does *NOT* make it treated like a number again.
	$int += 0;
	is($DB->_is_currently_numeric($int),1,"int is numeric again after += 0");

	my $float = 12.34;
	is($DB->_is_currently_numeric($float),1,"floating point scalar is numeric");

	# still just numbers, but I treated it like a string
	$float .= '5';
	is($DB->_is_currently_numeric($float),0,"float is not numeric after string concatination");

	# treated it like a number again
	$float++;
	is($DB->_is_currently_numeric($float),1,"float is numeric again after ++");
}

### DESIGN DOC
{
	my $dd;
	eval { $dd = CouchDB::Client::DesignDoc->new({
		id => '_design/foo', 
		data => {
			language => 'perl',
			views   => {
				all => { map => 'function (doc) {}'},
			},
		},
		db => $DB}); };
	ok !$@, 'different ctor works';
	eval { CouchDB::Client::DesignDoc->new({ id => 'foo', db => $DB }); };
	ok $@, "bad id blows: $@";
	eval { $dd->queryView('all'); };
	ok $@, "no connection blows: $@";
}

# CLIENT
{
	my $c;
	$c = CouchDB::Client->new({uri => 'http://test'});
	ok $c && $c->{uri} =~ m{/$}, "Trailing / added";
	$c = CouchDB::Client->new();
	ok $c && $c->{uri} eq 'http://localhost:5984/', 'Default URI';
	$c = CouchDB::Client->new(scheme => 'https', host => 'example.org', port => '9000');
	ok $c && $c->{uri} eq 'https://example.org:9000/', 'URI by fragments';
	$c = CouchDB::Client->new(json => JSON::Any->new, ua => LWP::UserAgent->new);
	ok $c && $c->{json} && $c->{ua}, 'helper objects';

	# bad address
	$c = CouchDB::Client->new(scheme => 'https');
	ok !$c->testConnection, "no connection";
	eval { $c->serverInfo };
	ok $@, "Could not connect for serverInfo: $@";
	eval { $c->listDBNames };
	ok $@, "Could not connect for listDBNames: $@";
}

