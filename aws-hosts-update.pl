#!/perl/bin/perl
#===============================================================================
#
#         File: aws-hosts-update.pl
#
#        Usage: aws-hosts-update.pl
#
#  Description: Fetch hosts from AWS and build an s-dialog compatible hosts file.
#
#       Author: Andy Harrison <domain=gmail,tld=com,uid=aharrison>
#      VERSION: 1.0
#      Created: 12/07/2014 11:11:04 AM
#===============================================================================

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long qw(:config auto_help);
use FileHandle;

use Curses;
use Curses::UI;
use Curses::UI::Common;

use JSON;
use YAML::Any qw(LoadFile);

my $HOME = $ENV{HOME};

# {{{ handle commandline options

our $opts = LoadFile( $ENV{HOME} . '/.s.conf' );

$opts->{debug}     = 0;
$opts->{verbose}   = 0;

# List of the tags we actually care about
#
$opts->{tags} = [ 'Environment', 'Purpose', 'Name', 'Cost Center', 'aws:cloudformation:stack-name' ];

my $key_aliases = {
    'Environment' => 'Env',
    'Cost Center' => 'Cost',
    'aws:cloudformation:stack-name' => 'CF',
};

GetOptions(
    $opts,
        'debug!',
        'verbose!',
        'awshostsfile=s',
);

our $debug = $opts->{debug};
our $debugfh;

if ( $debug ) {
    $debugfh = FileHandle->new('s-dialog.debuglog', '>>')
        or die "Error opening debuglog for writing: $!\n";
}

# }}}

# {{{ gather host info and create menu hash

our %hostinfo;

my $key = 1;

my $aws_json_response = qx(aws ec2 describe-instances --filters "Name=tag-key,Values=Name" );
my $json = JSON->new;

my $ec2 = $json->decode($aws_json_response);

ddump('ec2-first', $ec2) if $debug;

die "Error reading ec2 information...\n"
    unless 
            defined $ec2
        &&          $ec2
        &&  defined $ec2->{Reservations}
        &&          $ec2->{Reservations}
        &&      ref $ec2->{Reservations} eq 'ARRAY'
        && scalar @{$ec2->{Reservations}};

for my $reservation ( @{$ec2->{Reservations}} ) {

    if ( defined $reservation->{Instances}
         &&      $reservation->{Instances}
         &&  ref $reservation->{Instances} eq 'ARRAY'
    ) {

        my $instances = $reservation->{Instances};
        ddump('instances-first', $instances) if $debug;

        for my $i ( @$instances ) {

            # Make sure this instance's hashref has all the data we want.
            #
            next unless
                    defined $i
                &&          $i
                &&  defined $i->{State}
                &&          $i->{State}
                &&  defined $i->{State}->{Name}
                &&          $i->{State}->{Name}
                &&          $i->{State}->{Name} eq 'running'
                &&  defined $i->{Tags}
                &&          $i->{Tags}
                &&      ref $i->{Tags} eq 'ARRAY'
                && scalar(@{$i->{Tags}});


            my $name     = '';
            my $user     = 'ec2-user';
            my $hostname = $i->{PrivateIpAddress};

            my $ssh = $user . '@' . $hostname;

            my @tags;

            ddump( 'tagpair', $i->{Tags} ) if $debug;

            for my $tagpair ( @{$i->{Tags}}) {

                ddump( 'tagpair', $tagpair ) if $debug;

                my $key = $tagpair->{Key};

                next unless grep { $key eq $_ } @{$opts->{tags}};

                my $val =
                    defined $tagpair->{Value}
                    &&      $tagpair->{Value}
                          ? $tagpair->{Value}
                          : ''
                          ;
                
                $key =
                    defined $key_aliases->{$key}
                          ? $key_aliases->{$key}
                          : $key
                          ;

                $name = $val if $key eq 'Name';

                push @tags, $key . '=' . $val;

            }

            ddump( 'tags', \@tags ) if $debug;

            my $comment = ' #';
            $comment .= join( ' ', sort @tags);

            my $menuitem = $name ? $name : $hostname;
            $menuitem .= " (${user})";
            $menuitem .= $comment;

            $hostinfo{$key}{hostname} = $hostname;
            $hostinfo{$key}{ssh}      = $ssh;
            $hostinfo{$key}{user}     = $user;
            $hostinfo{$key}{comment}  = $comment;
            $hostinfo{$key}{menuitem} = $menuitem;

            ddump( 'hostinfo-key', $hostinfo{$key}) if $debug;

            $key++;

        }

    } else {
        print "Error:";
        ddump('ec2',$ec2) if $debug;
    }

    ddump( 'load_hosts', \%hostinfo ) if $debug;

} # }}}

my $awsfh = FileHandle->new($opts->{awshostsfile}, '>')
    or die "Error opening awshostsfile for writing: $!\n";

for my $curhost ( sort keys %hostinfo ) {

    my $line = 
          $hostinfo{$curhost}->{user} . '@' . $hostinfo{$curhost}->{hostname} . $hostinfo{$curhost}->{comment};

    print $awsfh "$line\n";

}

$awsfh->close;

# {{{ max
#
sub max {

    my ( $a, $b ) = @_;

    $a = 0 unless $a;

    return $a > $b
        ? $a
        : $b;

} # }}}

# {{{ ddump
#
sub ddump {

    my $label = shift;

    my $old = $Data::Dumper::Varname;

    $Data::Dumper::Varname = $label . '_';

    if ( ref $debugfh eq 'FileHandle' ) {
        print $debugfh Dumper( @_ );
    } else {
        print Dumper( @_ );
    }

    $Data::Dumper::Varname = $old;

} # }}}

# }}}

# {{{ END

__END__

# {{{ POD

=pod

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2014 Andy Harrison

You can redistribute and modify this work under the conditions of the GPL.

=cut

# }}}

# }}}

