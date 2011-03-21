################################################################################
#	Curl
################################################################################
#	libcurl based HTTP client
#	faster then LWP::UseAgent
#
#-------------------------------------------------------------------------------

package CouchDB::Curl;

use strict;
use WWW::Curl::Easy;
use JSON::XS;
use HTTP::Exception;
use Data::Dumper;
use URI;
use URI::Escape::XS 'encodeURIComponent';
use MIME::Base64;

use Exporter qw(import);
our @EXPORT_OK = qw(Curl JSONCall);

#-------------------------------------------------------------------------------
# Function: JSONCall
#	Call a resource using network stack, both sends and expects JSON.
#   Can use Basic Authorisation.
#
# Parameters:
#	$method  - one of GET,HEAD,POST,PUT,DELETE
#	$uri     - something like "http://server/resource"
#	$body    - hashref
#	$query   - hashref with query parameters
#				 (will be transformed to ?key=value&...)
#	$user    - username
#	$pwd     - password
#
# Returns:
# 	$hashref or HTTP::Exception
#-------------------------------------------------------------------------------
sub JSONCall {
	my ( $method, $uri, $body, $query, $user, $pwd ) = @_;

	my $auth = "Basic " . encode_base64("$user:$pwd", '');
	my $p = eval { encode_json($body) } if $body;
	HTTP::Exception->throw('400', "Error encoding data to JSON: $@") if $@;

	my $data = Curl(
		$method, $uri, $p,
		[
			"Authorization: $auth",
			"Accept: application/json",
			"Content-Type: application/json"
		],
		$query
	);

	my $r = eval { decode_json($data) } if $data;
	HTTP::Exception->throw('500', "Error parsing JSON input: $@") if $@;

	return $r;
}

#-------------------------------------------------------------------------------
# Function: Curl
# 	Make a HTTP call using libcurl library.
#
#	See all available libcurl options here:
#	 http://curl.haxx.se/libcurl/c/curl_easy_setopt.html
#
# Parameters:
#	$method  - one of GET,HEAD,POST,PUT,DELETE
#	$uri     - something like "http://server/resource"
#	$body    - encoded body
#	$headers - arrayref of headers (["Content-Type: text/yaml"])
#	$query   - hashref with query parameters 
#				 (will be transformed to ?key=value&...)
#
# Returns:
#	$data or HTTP::Exception - response body	
#-------------------------------------------------------------------------------
sub Curl {
	my ( $method, $uri, $body, $headers, $query ) = @_;

	my $curl = WWW::Curl::Easy->new;

	my $q = _CompileQuery($query);
	if ($q) {
		if ($uri =~ m/\?/) {
			$uri .= "&$q"; # in case some query is already present in uri
		} else {
			$uri .= "?$q";
		}
	}
	$curl->setopt( CURLOPT_URL, $uri );
	if ($body) {
		$curl->setopt( CURLOPT_POSTFIELDS, $body );
		$curl->setopt( CURLOPT_POSTFIELDSIZE, length $body );
	}
	$curl->setopt( CURLOPT_CUSTOMREQUEST, $method );
	$curl->setopt( CURLOPT_HTTPHEADER, $headers ) if $headers and @$headers > 0;

	my $response_body;
	$curl->setopt( CURLOPT_WRITEDATA, \$response_body );
	my $retcode = $curl->perform;
	if ( $retcode == 0 ) {
		my $status = $curl->getinfo(CURLINFO_HTTP_CODE);
		HTTP::Exception->throw($status, status_message => $response_body) if $status >= 300;
		return $response_body;
	}
	else {
		HTTP::Exception->throw(500, status_message => 
			    "An error happened: "
			  . $curl->strerror($retcode) . " "
			  . $curl->errbuf)
	}
}

#-------------------------------------------------------------------------------
# Function: _CompileQuery
#	Transform hash to URL query (behind "?")
#
# Parameters:
# 	hashref or scalar
#
# Returns:
# 	URL encoded string
#
#-------------------------------------------------------------------------------
sub _CompileQuery {
	my ($query) = @_;
	return undef unless $query;
	my $ref = ref $query;
	if ($ref eq 'SCALAR') {
		return $query;
	} elsif ($ref eq 'HASH') {
		my @params;
		foreach my $key ( sort keys %$query ) {
			my $v;
			my $vref = ref $query->{$key};
			if ( $vref and $vref ne 'SCALAR') {
				$v = encodeURIComponent(encode_json($query->{$key}));
			} else {
				$v = $query->{$key};
			}
			push @params,$key."=".$v;
		}
		return join( "&", @params );
	} else {
		HTTP::Exception->throw('400', "Unsupported query param, use HASH or SCALAR");
	}
}


1;

=pod

=head1 NAME

CouchDB::Curl - libcurl based HTTP client, faster then LWP::UserAgent

=head1 SYNOPSIS

	my $hash = JSONCall('GET', 'http://localhost/resource');

	JSONCall('POST','http://localhost/resource2', { hello => 'world' });
	if (my $e = HTTP::Exception->caught) {
        die $e->code . $e->status_message;
	}

	my $image = Curl('GET', 'http://localhost/image.png');


=head1 DESCRIPTION

This is a functional approach to HTTP client. It is based on libcurl which is faster then LWP::UserAgent. For example retrieving 1000 documents from CouchDB takes 6.3 seconds with LWP and just 3.3 with Curl.


=head1 METHODS

=over 8

=item Curl


=item JSONCall


=back

=head1 AUTHOR

Jiri Sedlacek, <jiri d.t sedlacek @t futu d.t cz>

=head1 BUGS


=head1 COPYRIGHT & LICENSE

Copyright 2008 Jiri Sedlacek, all rights reserved.

This library is free software; you can redistribute it and/or modify it under the same terms as
Perl itself, either Perl version 5.8.8 or, at your option, any later version of Perl 5 you may
have available.

=cut
