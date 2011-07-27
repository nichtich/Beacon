use strict;
use warnings;
package Beacon;
#ABSTRACT: A simple link aggregation file format

use Time::Piece;
use URI::Escape;
use URI::Template; # TODO
use Scalar::Util qw(blessed);
use URI;
use Carp;

our %META_FIELDS = (
    TARGET      => sub {
        my $t = shift;
        #$t .= '{ID}' unless $t =~ /{ID}/;
        #'URI::Template', # TODO
        #return URI::Template->new($t);
        return $t;
    },
    PREFIX      => sub { $_ = URI->new( shift )->canonical; $_ =~ /[^:+]:/ ? $_ : undef },
    PROPERTY    => sub { URI->new( shift )->canonical; },
    FORMAT      => sub { $_ = shift; s/^[A-Z]+-(BEACON)$/$1/; $_; },
    VERSION     => sub { $_[0] =~ /\d\.\d/ ? $_[0] : undef },
    FEED        => sub { $_ = URI->new(shift)->canonical; $_ =~ qr{^https?://[^.]+\..} ? $_ : undef; },
    CONTACT     => sub { shift },
    COUNT       => sub { $_[0] =~ /^\d+$/ ? (0 + $_[0]) : undef },
    INSTITUTION => sub { shift },
    DESCRIPTION => sub { shift },
    NAME        => sub { shift },
    TIMESTAMP   => \&_timestamp,
    REVISIT     => \&_timestamp,
    EXAMPLES    => sub { join '|', grep { $_ ne '' } split('|',$_) },
    MESSAGE     => sub { shift }, # may contain {hits}
    ONEMESSAGE  => sub { shift },
    SOMEMESSAGE => sub { shift },
# better remove or specify the following:
    ISIL        => sub { shift },
    UPDATE      => sub { shift },
#   REMARK, ALTTARGET, IMGTARGET ??
);

our $FIELD_NAME = qr/^[A-Z][A-Z0-9_]*$/;

sub new {
    my ($class, %attr) = @_;
    my $self = bless {
        meta   => { FORMAT => 'BEACON' },
        links  => { },
        count  => 0,
    }, $class;

    my @fields = grep { $_ =~ $FIELD_NAME } keys %attr;
    if (@fields) {
        $self->meta( map { $_ => $attr{$_} } @fields );
    }

    $self;
}

sub parse {
    my $self = shift;
    my %attr = @_ % 2 ? ( from =>  @_ ) : @_;
    my $from = $attr{from};

    $self->{meta} = { };
    $self->{count} = 0;
    $self->{links} = { };

    # read from different kind of input (scalar, code, STDIN, file)
    my $readline = sub { };
    if (not defined $from) {
        croak 'No input specified to parse from';
    } elsif (ref $from) {
        if (ref $from eq 'SCALAR') {
            my $lines = [ split("\n",$$from) ];
            $readline = sub { shift @$lines };
        } elsif (ref $from eq 'CODE') {
            $readline = $from;
        } else {
            croak 'Unknown input type '.ref($from).' to parse from';
        }
    } elsif( $from eq '-' ) {
        $readline = sub { readline *STDIN };
    } else {
        open(my $fh, "<:encoding(UTF-8)", $from) or croak "Failed to open file $from";
        $readline = sub { readline $fh };
    }


    # start parsing
    my ($linecount, $inheader) = (0,1);
    while ( $_ = $readline->() ) {
        s/[ \x0d\x0a]+$//; # trailing space and newlines of any kind
        unless ( $linecount++ ) {
            if ( s/^\x{FEFF}// ) { # BOM
            } elsif ( s/^\xef\xbb\xbf// ) { # BOM bytes
                croak "File contains double encoded UTF-8: $from";
            } elsif ( /^\s*$/ ) {
                # carp "Discarding blank line before BEACON header";
                next;
            };
        };
        if ( $inheader ) {
            if ( /^#(.*)$/ ) {
                if ( /^#([^:]+):(.*)$/ ) {
                    $self->meta( $1 => $2 );
                } else {
                    croak "Invalid header field in line $linecount: $_";
                }
                next;
            } else {
                $inheader = 0;
            }
        }
        $self->parselink( $_, $linecount );
    }

    # for method chaining
    $self;
}

sub parselink {
    my ($self, $line, $linecount) = @_;

    $line =~ s/^\s+|\s+$//g;
    my @fields = split(/\s*\|\s*/, $line);
    return if !@fields or $fields[0] eq '';

    @fields[1..3] = map { defined $_ ? $_ : '' } @fields[1..3];

    # TODO: check link
    #my $msg = $self->_checklink( @fields );
    #if ( $msg ) {
    #    $self->_handle_error( $msg ); 
    #    return;
   
    push @{ $self->{links}->{$fields[0]} }, [ @fields[1..3] ];
    $self->{count}++; 
}

sub expand {
    my ($self, @link) = @_;

    foreach (0..3) {
        $link[$_] = '' unless defined $link[$_];
    }

    my $id    = $link[0];
    my $label = $link[1];

    # TODO: document this expansion
    if ( $link[1] =~ /^[0-9]*$/ ) { # if label is number (of hits) or empty
        my $descr = $link[2];

        # TODO: handle zero hits
        my $msg = $self->{meta}->{$label eq '1' ? 'ONEMESSAGE' : 'SOMEMESSAGE'}
                || $self->{meta}->{'MESSAGE'};

        if ( defined $msg ) {
            _str_replace( $msg, '{id}', $id ); # unexpanded
            _str_replace( $msg, '{hits}', $link[1] );
            _str_replace( $msg, '{label}', $link[1] );
            _str_replace( $msg, '{description}', $link[2] ); 
            _str_replace( $msg, '{target}', $link[3] ); # unexpanded
        } else {
            $msg = $self->{meta}->{'NAME'} || $self->{meta}->{'INSTITUTION'};
        }
        if ( defined $msg && $msg ne '' ) {
            # if ( $link[1] == "") $descr = $label;
            $link[1] = $msg;
            $link[1] =~ s/^\s+|\s+$//g;
            $link[1] =~ s/\s+/ /g;
        }
    } else {
        _str_replace( $link[1], '{id}', $id ); # unexpanded
        _str_replace( $link[1], '{description}', $link[2] );
        _str_replace( $link[1], '{target}', $link[3] ); # unexpanded
        # trim label, because it may have changed
        $link[1] =~ s/^\s+|\s+$//g;
        $link[1] =~ s/\s+/ /g;
    }

    # expand source
    my $prefix = $self->{meta}->{PREFIX};
    $link[0] = $prefix . $link[0] if defined $prefix;
    $link[0] = '' unless _is_uri($link[0]);

    # expand target
    my $target = $self->{meta}->{TARGET};
    if (defined $target and ($link[3] eq '' or $target =~ /{TARGET}/)) {
         _str_replace( $target, '{ID}' => $id );
         _str_replace( $target, '{TARGET}' => $link[3] );
         $link[3] = $target;
    #$target->process_to_string( ID => $link[0], LABEL => $label, TARGET => $link[3] );
    #        my $source = $link[0];
    #        my $label = $link[1];
    #        $link[3] =~ s/{ID}/$source/g;
    #        $link[3] =~ s/{LABEL}/uri_escape($label)/eg;
    }

    return $link[0] ne '' ? @link : ('','','','');
}

sub _str_replace {
    $_[0] =~ s/\Q$_[1]\E/$_[2]/g;
}

sub condense {
    carp 'Not implemented yet';
}

sub count {
    return shift->{count};
}

sub count_ids {
    return scalar keys %{shift->{links}};
}

sub get {
    my ($self, $id) = @_;
    my $links = $self->{links}->{$id} or return;
    return wantarray ? @$links : $links->[0];
}

sub get_expanded {
    my ($self, $id) = @_;
    if (wantarray) {
        return map { [ $self->expand( $id, @$_ ) ] } $self->get($id);
    } else {
        my $l = $self->get($id) or return;
        return [ $self->expand( $id, @$l ) ];
    }
}

sub get_triple {
    my ($self, $id) = @_;
    # TODO: $id, property, $target
}

sub meta {
    my $self = shift;
    return %{$self->{meta}} unless @_;

    if (@_ == 1) {
        my $field = uc(shift);
        $field=~ s/^\s+|\s+$//g;
        return $self->{meta}->{$field}; # TODO: map blessed values to strings
    }

    croak 'Wrong number of arguments in ' . __PACKAGE__ . '::meta' if @_ % 2;

    my @args = @_;
    while (@args) {
        my $field = uc(shift @args);
        $field =~ s/^\s+|\s+$//g;
        croak "Invalid field name: $field" if $field !~ $FIELD_NAME;

        my $value = shift @args;
        if (defined $value) {
            $value =~ s/^\s+|\s+$//g;
        } else { 
            $value = '';
        }

        if ($value eq '') { # empty field: unset
            croak 'You cannot unset field FORMAT' if $field eq 'FORMAT';
            delete $self->{meta}->{$field};
            next;
        }

        if ( $META_FIELDS{$field} ) {
            my $normalized = $META_FIELDS{$field}->( $value );
            if (defined $normalized) {
                $value = $normalized;
            } else {
               croak "Invalid $field field: $value";
            }
        }

        $self->{meta}->{$field} = $value;
    }

    $self;
}


### helper methods

sub _timestamp {
    my $t = shift or return;
    if ($t =~ /^[0-9]+$/) { # seconds since epoch
        $t = gmtime($t); 
    } else { # ISO 8601 UTC (YYYY-MM-DDTHH:MM:SSZ)
        $t =~ s/Z$//;
        return unless $t = eval { Time::Piece->strptime($t,'%Y-%m-%dT%T') };
    }
    return $t->datetime.'Z';
};


sub _is_uri {
    my $value = $_[0];
    
    return unless defined($value);
    
    # check for illegal characters
    return if $value =~ /[^a-z0-9\:\/\?\#\[\]\@\!\$\&\'\(\)\*\+\,\;\=\.\-\_\~\%]/i;
    
    # check for hex escapes that aren't complete
    return if $value =~ /%[^0-9a-f]/i;
    return if $value =~ /%[0-9a-f](:?[^0-9a-f]|$)/i;
    
    # split uri (from RFC 3986)
    my ($scheme, $authority, $path, $query, $fragment)
      = $value =~ m|(?:([^:/?#]+):)?(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?|;

    # scheme and path are required, though the path can be empty
    return unless (defined($scheme) && length($scheme) && defined($path));
    
    # if authority is present, the path must be empty or begin with a /
    if (defined($authority) && length($authority)) {
        return unless (length($path) == 0 || $path =~ m!^/!);    
    } else {
        # if authority is not present, the path must not start with //
        return if $path =~ m!^//!;
    }
    
    # scheme must begin with a letter, then consist of letters, digits, +, ., or -
    return unless lc($scheme) =~ m{^[a-z][a-z0-9\+\-\.]*$};
    
    return $value;
}

1;

=head1 DESCRIPTION

This module implements a validating L</BEACON format> parser and serializer.
In short, a B<Beacon> is a set of links, together with some meta fields. Each
link at least consists of source URI (also referred to as C<id>) and a
C<target> URI. In addition it can have a C<label> (also refered to as message)
and a C<description> (also used as property).

=head1 BEACON format

A BEACON file is a UTF-8 encoded text file that contains a set of lines. It
begins with a set of unordered meta field lines, followed by a list of link
lines. Leading and trailing whitespace is removed from all lines, meta field
names, meta field values, and link parts (id, label, description, target)
before further processing. All lines before the first line not starting with a
hash symbol (C<#>) are treated as meta field lines and all remaining lines as
link lines. Empty lines are ignored, but they can indicate the end of meta
field lines.

=head2 meta field lines

Meta field lines start with a hash symbol (C<#>), followed by a meta field, a
colon (C<:>), and a meta field value. The following meta field with field name
C<FORMAT> and field value C<BEACON> should always be included in a BEACON file:

    #FORMAT: BEACON
    
Meta field names should be given in uppercase and must be converted to uppercase. 
A name must start with a letter (A-Z), optionally followed by any combination of
letters (A-Z), digits (0-9), and underscore (_). Meta field values can be any
Unicode strings, but whitespace is trimmed and line breaks are not possible.

There are some meta fields with predefined meaning:

=over 4

=item FORMAT

=item VERSION

=item TARGET

=item PREFIX

=item MESSAGE

=item ONEMESSAGE

=item SOMEMESSAGE

=item PROPERTY

=item NAME

=item DESCRIPTION

=item CONTACT

=item INSTITUTION

=item FEED

=item TIMESTAMP

=item REVISIT

=item EXAMPLES

=item COUNT

=back

=head2 link lines

A link line contains a list of one or more values, separated by a vertical bar
(|).  Only the first four values are respected. Missing values, if there are
less then four, are equal to the empty string (and to pure whitespace strings,
because all values are trimmed). The four values make the id, label,
description, and target of a E<raw link>. Raw link can be expanded based on the
meta fields. Link lines which do not result in valid links after expansion,
must be ignored or result in an error.

=head2 link expansion

PREFIX is prepended to the raw id. TARGET is used as template to construct a
new target, if the raw target is empty or if the TARGET template contains the
template parameter TARGET. MESSAGE, ONEMESSAGE, and SOMEMESSAGE, NAME, and
INSTITUTION are used to construct or modify a link label.

=method new ( { $field => $value } )

Creates a new, empty Beacon object, optionally with some given meta fields.

=method parse

Returns the Beacon object, so you can say:

  my $b = Beacon->new->parse( $file );

=method expand ( $id [, $label [, $message [, $target ] ] ] )

Expands a raw link, based on this BEACON's meta fields.

=method condense ( $id [, $label [, $message [, $target ] ] ] )

Returns a condense representation of a link in BEACON format, to be used for
serialization.

=method count

Returns the number of stored links.

=method count_ids

Returns the number of stored link ids. If this number is equal to the number of
stored links, each id has exactely one link, so you can use links as mapping.

=method get ( $id )

Returns a list of raw stored links for some id.

=method get_expanded ( $id )

Returns a list of expanded stored links for some id.

=method meta ( [ $field [ => $value ] )

Get and or set one or more meta fields. Field names are converted to uppercase.

=head1 UTILITY FUNCTIONS

=head2 _is_uri

Check whether a given string is an URI. This function is based on code of
L<Data::Validate::URI>, adopted for performance.

=head1 SEE ALSO

See L<http://meta.wikimedia.org/wiki/BEACON> for an English introduction to
BEACON.  This module is a rewrite of L<Data::Beacon> which got bloated because
it tried to combine too many things.

=head1 ACKNOWLEDGEMENTS

This module contains code snippets from Thomas Berger. BEACON was created
together with Mathias Schindler and Christian Thiele.

=cut
