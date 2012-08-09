#!/usr/bin/perl
#===============================================================================
#
#         File: s-dialog.pl
#
#        Usage: s-dialog.pl
#
#  Description:
#
#       Author: Andy Harrison <domain=gmail,tld=com,uid=aharrison>
#      VERSION: 1.0
#      Created: 05/09/2012 11:11:04 AM
#===============================================================================

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long qw(:config auto_help);
use FileHandle;

use Curses;
use Curses::UI;
use Curses::UI::Common;

use YAML::Any qw(LoadFile DumpFile);

my $HOME = $ENV{HOME};

# {{{ handle commandline options

our $opts = LoadFile( $ENV{HOME} . '/.s.conf' );

$opts->{debug}     = 0;
$opts->{verbose}   = 0;

# Make the effort to find a good editor
#
$opts->{editor} =
    defined $ENV{EDITOR}
    &&      $ENV{EDITOR}
    &&   -x $ENV{EDITOR}      ? $ENV{EDITOR}
       : -x "${HOME}/.editor" ? "${HOME}/.editor"
       : -x '/usr/bin/vim'    ? '/usr/bin/vim'
       : -x '/bin/vim'        ? '/bin/vim'
       : -x '/usr/bin/vi'     ? '/usr/bin/vi'
       : -x '/bin/vi'         ? '/bin/vi'
       : 'vim'
       ;

$opts->{bg}  = 'blue';
$opts->{bbg} = 'blue';
$opts->{bfg} = 'green';

GetOptions(
    $opts,
        'debug!',
        'verbose!',
        'screen=s',
        'editor=s',
        'ssh=s',
        'bbg=s',
        'bfg=s',
        'bg=s',
        'hostsfile=s',
);

our $debug = $opts->{debug};
our $debugfh;

if ( $debug ) {
    $debugfh = FileHandle->new('s-dialog.debuglog', '>>')
        or die "Error opening debuglog for writing: $!\n";
}

our $hostsfile =
    defined $opts->{hostsfile}
    &&      $opts->{hostsfile}
    &&   -e $opts->{hostsfile} && -r _
          ? $opts->{hostsfile}
          : -e $ENV{HOME} . '.hosts' && -r _
             ? $ENV{HOME} . '.hosts'
             : die "Error: can't find a readable hosts file!\n";

# }}}

# {{{ dispatch table
#
# Generally, any entries read from the hostsfile will be
# used to directly open an ssh session to the address parsed
# from that line.  However, this dispatch table is checked
# for a corresponding key first and if a corresponding
# coderef is found, it will be executed instead of treating
# it is a normal ssh host.
#
# In short, if you want something to appear in your screen
# menu that isn't actually a host, put a handler for it
# here.

my $do = {
           edit               =>    sub { editfile( $hostsfile )                            },
           editknownhosts     =>    sub { editfile("${HOME}/.ssh/known_hosts")              },
           editsshconfig      =>    sub { editfile("${HOME}/.ssh/config")                   },
           editcorelist       =>    sub { editfile("${HOME}/.hosts.coreservers")            },

           shell              =>    sub { screenlocal('shell')                              },
           root               =>    sub { screenlocal('root', 'sudo -s')                    },
           'zypper-shell'     =>    sub { screenlocal('zypper', 'sudo zypper shell')        },
           htop               =>    sub { screenlocal('htop', 'htop')                       },
           htoproot           =>    sub { screenlocal('htop', 'sudo htop')                  },
           toproot            =>    sub { screenlocal('top',  'sudo top')                   },
           notes              =>    sub { screenlocal('notes-gpg', 'notes.sh' )             },

           man                =>    sub { manpage()                                         },
           perldoc            =>    sub { perldoc()                                         },

           corelist           =>    sub { screenopenlist("${HOME}/.hosts.coreservers")      },

           '6shells'          =>    sub { screensource("${HOME}/.screenrc.shells")          },
           dhcpv6             =>    sub { screensource("${HOME}/.screenrc.hosts.dhcpv6")    },

           telnetviassh       =>    sub { telnetviassh()                                    },
           telnet             =>    sub { telnet()                                          },
           storage01          =>    sub { telnetviassh( 'storage01', 'storage01' )          },
           storage02          =>    sub { telnetviassh( 'storage02', 'storage02' )          },

           remotecmd          =>    sub { remotecmd()                                       },

};

ddump( 'dispatch_table', $do ) if $debug;

# }}}

# {{{ gather host info and create menu hash

our %hostinfo;
our %sshindex;

load_hosts({ hosts => $hostsfile });


# booooo...  fix this you lazy turd.
#
our %menuitems;
our @values;
our $inc_filter;

load_menuitems();

ddump( 'menuitems', \%menuitems ) if $debug;

# }}}

# {{{ create curses ui

my $cui = Curses::UI->new(
    -color_support => 1,
    -clear_on_exit => 1,
    -mouse_support => 1,
);


# Some default entries for the file menu.  I should come up
# with a better way to abstract this instead of hard coding
# these one-offs.
#
my @menu = (
    {   -label   => 'File',
        -submenu => [

                        { -label => 'Edit config       ',    -value => sub { editfile($hostsfile);                   $cui->layout(); } },
                        { -label => 'Edit known_hosts  ',    -value => sub { editfile("${HOME}/.ssh/known_hosts");   $cui->layout(); } },
                        { -label => 'Edit ssh config   ',    -value => sub { editfile("${HOME}/.ssh/config");        $cui->layout(); } },
                        { -label => 'Edit core list    ',    -value => sub { editfile("${HOME}/.hosts.coreservers"); $cui->layout(); } },

                        { -label => 'Exit            ^Q',    -value => \&exit_dialog },

                    ],
    },
);

my $menu = $cui->add(
    'menu', 'Menubar',
    -menu => \@menu,
    -fg   => 'white',
    -bg   => 'blue',
    -bbg  => 'blue',
    -bfg  => 'white',
);

my $win1 = $cui->add(
    'win1', 'Window',
    -border     => 1,
    -y          => 1,
    -bfg        => $opts->{bfg},
    -bbg        => $opts->{bbg},
    -bg         => $opts->{bg},
    -reverse    => 1,
);


my $listbox = $win1->add(
    'mylistbox', 'Listbox',
    -title    => 'MyListBox',
    -htmltext => 1,
    -values   => \@values,
    -labels   => \%menuitems,
    -radio    => 1,
    -onchange => \&listbox_callback,
    -bfg      => $opts->{bfg},
    -bbg      => $opts->{bbg},
    -bg       => $opts->{bg},
);


$win1->add(
    'listboxlabel', 'Label',
    -y     => -1,
    -bold  => 1,
    -text  => "Select any option in one of the listboxes please....",
    -width => -1,
);

# {{{ key bindings

# {{{ Bind keys to automatically do incr searching...
#
$cui->set_binding( sub { incremental_filter('a') }, 'a' );
$cui->set_binding( sub { incremental_filter('b') }, 'b' );
$cui->set_binding( sub { incremental_filter('c') }, 'c' );
$cui->set_binding( sub { incremental_filter('d') }, 'd' );
$cui->set_binding( sub { incremental_filter('e') }, 'e' );
$cui->set_binding( sub { incremental_filter('f') }, 'f' );
$cui->set_binding( sub { incremental_filter('g') }, 'g' );
$cui->set_binding( sub { incremental_filter('h') }, 'h' );
$cui->set_binding( sub { incremental_filter('i') }, 'i' );
$cui->set_binding( sub { incremental_filter('j') }, 'j' );
$cui->set_binding( sub { incremental_filter('k') }, 'k' );
$cui->set_binding( sub { incremental_filter('l') }, 'l' );
$cui->set_binding( sub { incremental_filter('m') }, 'm' );
$cui->set_binding( sub { incremental_filter('n') }, 'n' );
$cui->set_binding( sub { incremental_filter('o') }, 'o' );
$cui->set_binding( sub { incremental_filter('p') }, 'p' );
$cui->set_binding( sub { incremental_filter('q') }, 'q' );
$cui->set_binding( sub { incremental_filter('r') }, 'r' );
$cui->set_binding( sub { incremental_filter('s') }, 's' );
$cui->set_binding( sub { incremental_filter('t') }, 't' );
$cui->set_binding( sub { incremental_filter('u') }, 'u' );
$cui->set_binding( sub { incremental_filter('v') }, 'v' );
$cui->set_binding( sub { incremental_filter('w') }, 'w' );
$cui->set_binding( sub { incremental_filter('x') }, 'x' );
$cui->set_binding( sub { incremental_filter('y') }, 'y' );
$cui->set_binding( sub { incremental_filter('z') }, 'z' );
$cui->set_binding( sub { incremental_filter('0') }, '0' );
$cui->set_binding( sub { incremental_filter('1') }, '1' );
$cui->set_binding( sub { incremental_filter('2') }, '2' );
$cui->set_binding( sub { incremental_filter('3') }, '3' );
$cui->set_binding( sub { incremental_filter('4') }, '4' );
$cui->set_binding( sub { incremental_filter('5') }, '5' );
$cui->set_binding( sub { incremental_filter('6') }, '6' );
$cui->set_binding( sub { incremental_filter('7') }, '7' );
$cui->set_binding( sub { incremental_filter('8') }, '8' );
$cui->set_binding( sub { incremental_filter('9') }, '9' );
$cui->set_binding( sub { incremental_filter('-') }, '-' );
$cui->set_binding( sub { incremental_filter('.') }, '.' );

$cui->set_binding( sub { incremental_filter('KEY_BACKSPACE') }, KEY_BACKSPACE );

# }}}

$cui->set_binding( sub { $menu->focus() }, "\cX", KEY_F(10), KEY_F(9) );
$cui->set_binding( sub { $inc_filter = '';  load_menuitems(); $cui->layout() }, "\cL" );

$cui->set_binding(
    sub {
        $inc_filter = '';
        load_hosts({ hosts => $hostsfile });
        load_menuitems();
        $cui->layout();
    },
    "\cR"
);

$listbox->set_binding( \&exit_dialog, "\cC", "\cQ" );
$listbox->set_routine( 'option-select',  \&handle_choice );

$listbox->set_routine( 'space-select', \&space_handler );
$listbox->set_binding( 'space-select', CUI_SPACE );

#$listbox->set_routine( 'search-forward', \&search_forward);
#$listbox->set_binding( 'search-forward'  , '/' );

$listbox->set_binding( \&filter_dialog, "\cF", '/' );

# }}}

# }}}

my @selected;
my $choice;
my $filter_string;

while (1) {

    $listbox->focus();
    $cui->mainloop();

}


# {{{ subs
#

# {{{ filter_dialog
#
# TODO
#
# Awfully clunky way of doing this...
#
sub filter_dialog {

    ddump( '(filter_dialog) @_', @_ ) if $debug;

    my $fid    = 'filterdialog';
    my $flabel = 'Enter Filter expression';

    $filter_string = $cui->question($flabel);

    ddump( '(filter_dialog) filter_string', $filter_string ) if $debug;

    if ( $filter_string && $filter_string !~ m/^[*]$/ ) {

        load_menuitems($filter_string);

    } else {

        # Repopulate the menuitems global hash if we don't
        # specify a search filter.
        #
        load_menuitems();

    }

    # Put cursor back at the top of the list, then refresh the listbox.
    #
    $listbox->{-ypos} = 0;

    $listbox->draw;

    ddump( '(filter_dialog) menuitems after', \%menuitems ) if $debug;
    ddump( '(filter_dialog) values after', \@values ) if $debug;

} # }}}

# {{{ listbox_callback
#
sub listbox_callback {

    my $l = shift;
    my $lab = $l->parent->getobj('listboxlabel');
    my @sel = $listbox->get;

    @sel = ('<none>') unless @sel;

    ddump( '(listbox_callback) @sel', \@sel ) if $debug;

    $choice = join( ', ', @sel );;

    my $sel = "Selected: $choice\n";


    ddump( '(listbox_callback) sel', $sel ) if $debug;
    $lab->text($listbox->title . " $sel");

} # }}}

# {{{ sublistbox_callback
#
# Not currently used...
#
sub sublistbox_callback {

    my $l = shift;
    my $lab = $l->parent->getobj('listboxlabel');
    my @sel = $l->get;

    @sel = ('<none>') unless @sel;

    ddump( '(listbox_callback) @sel', \@sel ) if $debug;

    my $itemchoice = join( ', ', @sel );

    my $sel = "Selected: $choice\n";


    ddump( '(listbox_callback) sel', $sel ) if $debug;
    $lab->text($listbox->title . " $sel");

} # }}}

# {{{ handle_choice
#
sub handle_choice {

    # The first argument should be the appropriate cui object.
    #
    my $this = shift;

    my $scr = $this->{-canvasscr};

    ddump( 'handle_choice_this_ypos', $this->{-ypos} ) if $opts->{debug};

    # Get the selected element id.
    #
    $this->{-selected} = $this->{-ypos};

    # from the object, get the actual id number of the entry.
    #
    my $id = $this->get;

    ddump( 'handle_choice_id', $id ) if $debug;

    # Blank out the selection so it doesn't interfere later.
    #
    $this->{-selected} = undef;


    # Check and see if there's a corresponding item in the dispatch table
    #
    if ( defined $do->{$hostinfo{$id}{ssh}} ) {

        ddump( 'matched dispatched table with hostinfo', $hostinfo{$id}{hostname} ) if $opts->{debug};
        ddump( 'Matched dispatch table with menuitem',   $menuitems{$id} )          if $opts->{debug};

        # We found a corresponding entry in the dispatch table, so go ahead
        # and execute it...
        #
        $do->{$hostinfo{$id}{ssh}}->();

    } else {

        ddump( 'NOT matched dispatched table with hostinfo', $hostinfo{$id}{hostname} ) if $opts->{debug};
        ddump( 'NOT Matched dispatch table with menuitem',   $menuitems{$id} )          if $opts->{debug};

        # Otherwise, we assume that the entry is a hostname and that we want
        # to ssh into it...
        #
        screenopen(
            
            defined $hostinfo{$id}{title}
            &&      $hostinfo{$id}{title}
                  ? $hostinfo{$id}{title}
                  : $hostinfo{$id}{ssh},
            
            $hostinfo{$id}{ssh}

        );

    }

    # Put cursor back at the top of the list, then refresh the curses screen.
    #
    $this->{-ypos} = 0;

    $cui->layout();

    return;

} # }}}

# space_handler {{{
#
sub space_handler {

    # The first argument should be the appropriate cui object.
    #
    my $this = shift;

    ddump( 'space_handler_this', $this ) if $debug;

    my $scr = $this->{-canvasscr};

    # Get the selected element id.
    #
    $this->{-selected} = $this->{-ypos};


    # from the object, get the actual id number of the entry.
    #
    my $id = $this->get;

    ddump( 'space_handler_id', $id ) if $debug;

    # Blank out the selection so it doesn't interfere later.
    #
    $this->{-selected} = undef;

    screenselect($id);

} # }}}

# {{{ incremental_filter
#
sub incremental_filter {

    my $arg = shift;

    if ( defined $arg && $arg ) {
        if ( $arg eq 'KEY_BACKSPACE' ) {
            chop($inc_filter);
        } else {
            $inc_filter .= $arg;
        }
    }

    load_menuitems($inc_filter);

    # Put cursor back at the top of the list, then refresh
    # the listbox.
    #
    $listbox->{-ypos} = 0;

    $listbox->draw;


} # }}}

# {{{ exit_dialog
#
sub exit_dialog {

    ddump( 'exit_dialog_start', 1 ) if $opts->{debug};

    my $return = $cui->dialog(
                               -message => 'Quit?',
                               -title   => 'Are you sure?',
                               -buttons => [ 'yes', 'no' ],
                               -bbg     => $opts->{bbg},
                               -bfg     => 'red',
                               -bg      => $opts->{bg},
                             );

    ddump( '(exit_dialog)@selected', \@selected ) if $debug;
    ddump( '(exit_dialog)choice',    $choice )    if $debug;

    clear_exit() if $return;

} # }}}

# {{{ load_hosts
#
# This function reads the desired hostsfile and turns it into the various
# components of our menu.  So the end result will be something like:
#
# $hostinfo->{
#
#       00001 => {
#           hostname  => 'server1.example.com',                                     # the parsed hostname
#           user      => 'jsmith',                                                  # the parsed username
#           comment   => 'The primary mail server',                                 # a comment that will only appear in the menu
#           ssh       => 'jsmith@server1.example.com',                              # the actual string that will be fed to the ssh command
#           menuitem  => 'server1.example.com (jsmith) # The primary mail server',  # the name as it will appear in the menu and of the screen window itself
#       },
#
# };
#
# Then, when that hashref is turned into a simpler hashref of menuitems to be
# fed to Curses::UI and it will look like:
#
# $menuitems->{ }
#       00001 => 'server1.example.com (jsmith) # The primary mail server',
# };
#
sub load_hosts {

    my $args = shift;

    my $hosts =
        defined $args->{hosts}
        &&      $args->{hosts}
        &&   -r $args->{hosts} && -s _
              ? $args->{hosts}
              : die "hosts file not found, empty, or not readable.\n"
              ;


    # We're going to build the hash of host info using a
    # numeric key so that we can preserve the current order
    # of the file.
    #
    my $key = 1;
    my $maxwidth;

    my $hostsfh = FileHandle->new($hosts, 'r')
        or die "Error opening hosts file: $!\n";

    while ( <$hostsfh> ) {

        chomp;

        # ignore lines that are nothing but comments
        #
        next if m/^\s*#/;

        my $username;
        my $hostname;
        my $ssh;
        my $port;
        my $comment;

        my $listmatch = $_;

        # if found, pull out the username
        #
        if (m/^(.*?)[@](.*)$/s) {
            $username = $1;
            s/^.*?[@]//s;
        }

        # if found, pull out the port
        #
        if (m/[:](\d+)/s) {
            $port = $1;
            s/[:]\d+//s;
        }


        # if found, pull out the comment.
        #
        if (m/^.*?#\s*(.*)$/s) {
            $comment = $1;
            s/\s*#\s*(.*)$//s;
            $listmatch =~ s/\s*#\s*(.*)$//s;
        }

        # anything left will be the hostname
        #
        s/^\s+//;
        s/\s+$//;
        $hostname = $_;

        $hostinfo{$key}{hostname} = $hostname;

        my $len = length $hostname;

        if ($username) {
            $hostinfo{$key}{user} = $username;
            $len += length $username;
            $len += 3; # parens and space
        }

        # As we iterate, keep track of the maximum size of a
        # hostname/username combination.
        #
        $maxwidth = max( $maxwidth, $len );

        if ($comment) {
            $hostinfo{$key}{comment} = $comment;
        }

        $hostinfo{$key}{ssh} =
            defined $port
            &&      $port
                ? " -p ${port} "
                : ''
                ;

        $hostinfo{$key}{ssh} .=
                  $username
                ? $username . '@' . $hostname
                : $hostname
                ;

        $sshindex{$listmatch} = $key;

        $key++;

    }

    ddump( 'maxwidth_detected', $maxwidth ) if $opts->{debug};

    $maxwidth += 10;

    # Now iterate the hostinfo once again to pretty up the the list for
    # display in the actual curses menu.
    #
    for ( keys %hostinfo ) {

        $hostinfo{$_}{title} = $hostinfo{$_}{hostname};

        $hostinfo{$_}{menuitem} = ' ' x 2 . '<dim>' . $hostinfo{$_}{hostname} . '</dim>';

        my $len = length $hostinfo{$_}{hostname};

        if ( defined $hostinfo{$_}{user} ) {

            $hostinfo{$_}{title} .= ' (' . $hostinfo{$_}{user} . ')';

            $hostinfo{$_}{menuitem} .= ' (<underline>' . $hostinfo{$_}{user} . '</underline>)';
            $len += length $hostinfo{$_}{user};
            $len += 2; # parens and space
            $len++;
        }

        my $pad =
            $maxwidth - $len > 2
                ? $maxwidth - $len
                : 2
                ;

        ddump( 'pad_calc_item', $hostinfo{$_} ) if $opts->{debug};
        ddump( 'pad_calc_len',  $len )       if $opts->{debug};
        ddump( 'pad_calc_pad',  $pad )       if $opts->{debug};

        if ( defined $hostinfo{$_}{comment} ) {

            $hostinfo{$_}{title} .= ' # ' . $hostinfo{$_}{comment};

            $hostinfo{$_}{menuitem} .= ' ' x $pad;
            $hostinfo{$_}{menuitem} .= '<bold># ' . $hostinfo{$_}{comment} . '</bold>';
        }


    }


    ddump( 'load_hosts', \%hostinfo ) if $debug;
    ddump( 'sshindex',   \%sshindex ) if $debug;

    ddump( 'load_hosts_test_220', $hostinfo{220} ) if $opts->{debug};


} # }}}

# {{{ load_menuitems
#
sub load_menuitems {

    my $filter = shift;

    %menuitems = ();

    for ( sort { $a <=> $b } keys %hostinfo ) {

        ddump( 'load_menuitems_current_key', $_ ) if $debug;

        if ( $filter ) {
            if ( $hostinfo{$_}{menuitem} =~ m/$filter/i ) {
                $menuitems{$_} = $hostinfo{$_}{menuitem};
            }
        } else {
            $menuitems{$_} = $hostinfo{$_}{menuitem};
        }

    }

    @values = sort { $a <=> $b } keys %menuitems;

    ddump( 'load_menuitems_updated_values_list', \@values ) if $opts->{debug};



} # }}}

# sublistbox {{{
#
sub sublistbox {

    my $file = shift;
    my $func = shift;

    ddump( 'sublistbox_file', $file ) if $opts->{debug};
    ddump( 'sublistbox_func', $func ) if $opts->{debug};

    die "File for sublistbox not found...\n"
        unless -r $file && -s _;


    my $fh = FileHandle->new($file, 'r')
        or die "Error opening file for sublistbox: $!\n";

    my %subitems;

    my $key = 1;

    while ( <$fh> ) {

        chomp;

        # ignore lines that are nothing but comments
        #
        next if m/^\s*#/;

        # if found, pull out the comment.
        #
        if ( m/^.*?#\s*(.*)$/s ) {
            s/\s*#\s*(.*)$//s;
        }

        s/^\s+//;
        s/\s+$//;

        ddump( 'sublistbox_while_cur_key',     $key ) if $opts->{debug};
        ddump( 'sublistbox_while_cur_default', $_ )   if $opts->{debug};

        $subitems{$key} = $_;

        $key++;
    }

    ddump( 'sublistbox_subitems_count', scalar keys %subitems ) if $opts->{debug};

    my @itemvalues = sort { $a <=> $b } keys %subitems;

    ddump( 'sublistbox_itemvalues_count', scalar @itemvalues ) if $opts->{debug};

    ddump( 'sublistbox_before_adding_to_win1', 1 ) if $opts->{debug};
    my $sublistbox = $win1->add(
        'sublistbox', 'Listbox',
        -title    => 'ListBoxChooser',
        -htmltext => 1,
        -values   => \@itemvalues,
        -labels   => \%subitems,
       #-radio    => 1,
        -onchange => &$func,
        -bfg      => $opts->{bfg},
        -bbg      => $opts->{bbg},
        -bg       => $opts->{bg},
        -pad      => 10,
    );
    ddump( 'sublistbox_after_adding_to_win1', 1 ) if $opts->{debug};

    ddump( 'sublistbox_before_draw', 1 ) if $opts->{debug};
    $sublistbox->set_routine( 'option-select',  $func->() );

    #$sublistbox->draw();
    $sublistbox->focus();
    #$cui->layout();

    ddump( 'sublistbox_after_draw', 1 ) if $opts->{debug};
    my $sel = $sublistbox->get;
    ddump( 'sublistbox_sel', $sel ) if $opts->{debug};

    ddump( 'sublistbox_after_get', 1 ) if $opts->{debug};
    $cui->delete( 'sublistbox' );

    ddump( 'sublistbox_after_delete', 1 ) if $opts->{debug};
    $cui->layout();
    ddump( 'sublistbox_after_layout', 1 ) if $opts->{debug};


} # }}}

# {{{ max
#
sub max {

    my ( $a, $b ) = @_;

    $a = 0 unless $a;

    return $a > $b
        ? $a
        : $b;

} # }}}

# {{{ DISPATCH TABLE FUNCTIONS
#

# {{{ editfile
#
sub editfile {

    my $fn  = shift;
    my $cli = $opts->{editor} . " ${fn}";

    system($cli);

} # }}}

# {{{ screenlocal
#
sub screenlocal {

    my $title = shift;
    my $cmd   = shift;


    my $cli = $opts->{screen};

    $cli .=
        $title
        ? " -t '${title}' "
        : ''
        ;


    $cli .=
        $cmd
        ? " ${cmd}"
        : ''
        ;

    ddump( 'screenlocal_cli', $cli ) if $opts->{debug};

    system($cli);

} # }}}

# {{{ screenopen
#
sub screenopen {

    my $title = shift;
    my $host  = shift;

    $host = $title
        unless $host;

    die "screenopen host param error...\n"
        unless $host;

    my $cli = $opts->{screen} . " -t '${title}' " . $opts->{ssh} . " ${host}";

    system($cli);

} # }}}

# {{{ screenselect
#
sub screenselect {

    my $id = shift;

    ddump( 'screenselect', $id ) if $debug;

    die "screeselect param error...\n"
        unless $id;

    my $selection =
        defined $hostinfo{$id}{hostname}
        &&      $hostinfo{$id}{hostname}
              ? $hostinfo{$id}{hostname}
              : die "Corresponding hostname entry not found for: ${id}\n"
              ;

    my $cli = $opts->{screen} . " -X select ${selection}";

    ddump( 'screenselect_cli', $cli ) if $debug;

    system($cli);

} # }}}

# {{{ manpage
#
sub manpage {

    my $man  = shift;
    my $args = shift;

    my $manargs =
        defined $args && $args
        ? $args
        : ''
        ;

    my $mid    = 'mandialog';
    my $mlabel = 'Enter man page';

    my $man_string = $cui->question($mlabel);

    my $cli = $opts->{screen} . " -t manpage-${man_string} man ${manargs} ${man_string}";

    system($cli);

} # }}}

# {{{ perldoc
#
sub perldoc {

    my $pod  = shift;
    my $args = shift;

    my $podargs =
        defined $args && $args
        ? $args
        : ''
        ;

    my $mid    = 'poddialog';
    my $mlabel = 'Enter pod page';

    my $pod_string = $cui->question($mlabel);

    my $cli = $opts->{screen} . " -t perldoc-${pod_string} perldoc ${podargs} ${pod_string}";

    system($cli);

} # }}}

# {{{ new_perldoc
#
sub new_perldoc {

    my $pod  = shift;
    my $args = shift;

    my $podargs =
        defined $args && $args
        ? $args
        : ''
        ;

    ddump( 'perldoc executed', 1 );

    my $func = sub {

    };

    sublistbox(
        '/home/aharrison/.tcshrc.d/etc/podlist.txt',
        sub {

                ddump( 'perldoc_coderef_called', \@_ ) if $opts->{debug};
                my $lb = shift;
                ddump( 'perldoc_lb', $lb ) if $opts->{debug};
                ddump( 'perldoc_ref_lb', ref $lb ) if $opts->{debug};
                my $podchoice = $lb->get;

                my $cli = $opts->{screen}
                    . " -t perldoc-${podchoice} "
                    . " perldoc ${podchoice}";
                system($cli);
            }
    );

#   return;

#   my $pid    = 'perldocdialog';
#   my $plabel = 'Enter perldoc page';

#   my $perldoc_string = $cui->question($plabel);

#   my $cli = $opts->{screen} . " -t perldoc-${perldoc_string} perldoc ${podargs} ${perldoc_string}";

#   system($cli);

} # }}}

# {{{ screenopenlist
#
sub screenopenlist {

    my $fn = shift;

    die "Invalid file...\n"
        unless -f $fn && -r _ && -s _;

    my $fh = FileHandle->new($fn, '<')
        or die "Error opening file: $!\n";

    while ( <$fh> ) {

        chomp;
        next if m/^\s*#/;
        next if m/\s+/;


        if ( defined $sshindex{$_} && $sshindex{$_} ) {

            my $key = $sshindex{$_};

            # Otherwise, we assume that the entry is a
            # hostname and that we want to ssh into it...
            #
            screenopen(
                
                defined $hostinfo{$key}{hostname}
                &&      $hostinfo{$key}{hostname}
                      ? $hostinfo{$key}{hostname}
                      : $hostinfo{$key}{ssh},
                
                $hostinfo{$key}{ssh}
    
            );


        } else {

        my $cli = $opts->{screen} . " -t '${_}' " . $opts->{ssh} . " ${_}";
            ddump( 'screenopenlist_cli', $cli ) if $opts->{debug};
            system($cli);

        }


        # Keep from spawning too fast...
        #
        sleep 1;

    }


} # }}}

# {{{ screensource
#
sub screensource {

    my $fn = shift;

    my $cli = $opts->{screen} . " -X source ${fn}";

    system($cli);

} # }}}

# {{{ telnet
#
sub telnet {

    my $title = shift;
    my $host  = shift;

    $host = $title
        unless $host;

    my $cli = $opts->{screen} . " -t '${title}' telnet ${host}";

    system($cli);


} # }}}

# {{{ telnetviassh
#
sub telnetviassh {

    my $title        = shift;
    my $host         = shift;
    my $sshproxyhost = shift;

    die "Error, missing telnetviassh params...\n"
        unless $title && $host;

    $sshproxyhost =
        ! $sshproxyhost
        && defined $opts->{sshproxyhost}
        &&         $opts->{sshproxyhost}
                 ? $opts->{sshproxyhost}
                 : die "sshproxyhost undefined...\n"
                 ;

   my $cli = $opts->{screen} . " -t ${title}  --  " . $opts->{ssh} . " -t ${sshproxyhost}  -x telnet ${host}";

   system($cli);

} # }}}

# }}}

# {{{ clear_exit
#
sub clear_exit {

    Curses::initscr();
    Curses::refresh();

    exit;

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

=head1 NAME

s-dialog - Dialog for launching GNU screen sessions

=head1 SCRIPT CATEGORIES

Unix/System_administration

=head1 README

Provides a dialog box for launching new screen windows primarily focused
ssh sessions connecting to many hosts.  It's intended to be executed with
little to no commandline options.  It will simply stay running in your screen
window 0 all the time, so just switch to screen 0 to get back to this dialog screen.

=head1 OSNAMES

any

=head1 PREREQUISITES

 Curses::UI
 Curses
 YAML::Any

=head1 SYNOPSIS

=head2 OPTIONS AND ARGUMENTS

OPTIONS

=over 15

=item B<--hostsfile> I<filename>

The filename from which to read all the hosts so that we can build our menu.

=item B<--screen> I<filename>

Specify an screen binary. (default: /usr/bin/screen)

=item B<--editor> I<filename>

Specify an alternate editor. (default: $EDITOR, vim, or vi)

=back

SHORTCUTS

When the main menu is showing, here are the default key bindings:

=over 15

=item B<F9> | B<F10>

Bring up the file menu.

=item B</>

Add a filter to list of hosts so that only certain ones are showing.  Enter a blank filter to return to displaying the entire list.  Valid perl regex allowed.

=item B<CTRL-L>

Clear any filters and refresh the screen.

=item B<CTRL-R>

Clear any filters, re-read the hostsfile, and refresh the screen.

=item B<CTRL-Q>

Quit

=item B<a-z0-9>

Starts filtering the list in real time.  (CTRL-L will clear the filter).

=back

=head1 CONFIGURATION

The primary configuration containing hostnames (and other menuitems) can look like this:

 server1.example.com
 jsmith@server2.example.com
 oper@server2.example.com
 server3.example.com # the backup web server
 admin@server4.example.com:2022
 # comments will be skipped

(The order of items in this file will be preserved.)

Additionally, the file ~/.hosts.coreservers can be populated with items to be passed directly to ssh, so that you can open up sessions on a large number of servers all at once.

There is a sleep time of 1 second in between spawning because if you're in an environment where you use nfs mounted home directories on your servers, lighting up all those sessions at once will cause xauth to have a fit.

Other items that are allowed to appear in your default file containing your menuitems:

=over 15

=item B<shell>

No ssh anywhere, just like the screen 'create' command.  Convenient really only if it's your first menu item.

=item B<edit>

This will launch an editor on the menu file itself.

=item B<editknownhosts>

Edit your ~/.ssh/known_hosts file

=item B<editsshconfig>

Edit your ~/.ssh/config file

=item B<editcorelist>

Edit your ~/.hosts.coreservers file.

=item B<zypper-shell>

Launch a zypper shell, for if you're an openSUSE user.

=item B<man>

It will ask for the name of a man page and then display it in a separate screen window.

=back

=head1 TODO

=over 15

=item write more docs

=item fix ugly menuitems, values, and hostinfo globals.

=item try to work around the shortcomings of Curses::UI so this can have more visual appeal.

=back

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2012 Andy Harrison

You can redistribute and modify this work under the conditions of the GPL.

=cut

# }}}


# }}}

