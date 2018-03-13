package Koha::Plugin::Com::ByWaterSolutions::ItemRecalls;

## It's good practive to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

use Text::CSV;
use JSON;
use YAML;

use C4::Letters;
use C4::Accounts qw( manualinvoice );
use Koha::Holds;
use Koha::Notice::Messages;
use Koha::Patron::Debarments;
use Koha::DateUtils qw( dt_from_string );

# This block allows us to load external modules stored within the plugin itself
# In this case it's Template::Plugin::Filter::Minify::JavaScript/CSS and deps
# cpanm --local-lib=. -f Template::Plugin::Filter::Minify::CSS from asssets dir
BEGIN {
    use Config;
    use C4::Context;

    my $pluginsdir = C4::Context->config('pluginsdir');
    my $plugin_libs = '/Koha/Plugin/Com/ByWaterSolutions/ItemRecalls/lib/perl5';
    my $local_libs = "$pluginsdir/$plugin_libs";

    unshift( @INC, $local_libs );
    unshift( @INC, "$local_libs/$Config{archname}" );
}

## Here we set our plugin version
our $VERSION = "{VERSION}";

our $metadata = {
    name            => 'Item Recalls',
    author          => 'Kyle M Hall',
    description     => 'Adds the ability to create recalls in Koha.',
    date_authored   => '2018-02-26',
    date_updated    => '1900-01-01',
    minimum_version => '16.05',
    maximum_version => undef,
    version         => $VERSION,
};

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{cgi};

    my $dbh = C4::Context->dbh;

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'configure.tt' } );

        my $query = q{SELECT * FROM plugin_data WHERE plugin_class = 'Koha::Plugin::Com::ByWaterSolutions::ItemRecalls'};
        my $sth = $dbh->prepare( $query );
        $sth->execute();
        my $data;
        while ( my $r = $sth->fetchrow_hashref ) {
            $data->{ $r->{plugin_key} } = $r->{plugin_value}
        }

        $template->param(%$data);

        print $cgi->header(
            {
                -type     => 'text/html',
                -charset  => 'UTF-8',
                -encoding => "UTF-8"
            }
        );
        print $template->output();
    }
    else {
        my $data = { $cgi->Vars };
        delete $data->{ $_ } for qw( method save class );

        $self->update_syspref( 'opacuserjs',     $data );
        $self->update_syspref( 'intranetuserjs', $data );

        $dbh->do(q{DELETE FROM plugin_data WHERE plugin_key LIKE "enable%" AND plugin_class = 'Koha::Plugin::Com::ByWaterSolutions::ItemRecalls'});
        $self->store_data($data);

        $self->go_home();
    }
}

sub api {
    my ( $self, $args ) = @_;
    my $cgi = $self->{cgi};

    my $reserve_id = $cgi->param('reserve_id');
    my $action = $cgi->param('action');

    my $rules = $self->retrieve_data('recall_rules') . "\n";
    $rules = YAML::Load( $rules );

    my $hold = Koha::Holds->find( $reserve_id );

    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("SELECT * FROM plugin_recalls WHERE reserve_id = ?");
    $sth->execute( $hold->id );
    my $recall = $sth->fetchrow_hashref;

    my $rule;

    if ( !$recall && $hold && $hold->itemnumber && $hold->item->checkout && $hold->priority eq '1' ) { # Recalls only work for item level holds
        my $item = $hold->item;
        foreach my $r (@$rules) {
            my $it_match =  !$r->{itemtype} || $r->{itemtype} eq $item->itype;
            my $cc_match =  !$r->{categorycode} || $r->{categorycode} eq $item->ccode;
            my $bc_match =  !$r->{branchcode} || $r->{branchcode} eq $hold->branchcode;

            if ( $it_match && $cc_match && $bc_match ) {
                $rule = $r;
                last;
            }
        }
    }

    my $can_recall = $rule ? 1 : 0;

    my $data;
    if ( $action eq 'can_item_be_recalled' ) {
        $data->{can_recall} = $can_recall;
    }
    elsif ( $action eq 'recall_item' ) {
        if ($can_recall) {
            my $item     = $hold->item;
            my $checkout = $item->checkout;
            my $patron   = $checkout->patron;

            my $date_due = dt_from_string( $checkout->date_due );
            my $new_date_due =
              dt_from_string()->add( days => $rule->{due_date_length} );

          # Don't update date due if it is already due soon then date_due_length
            if ( $date_due > $new_date_due ) {
                $checkout->date_due($new_date_due);
                $checkout->store() or $data->{warning} = 'Unable to reduce due date';
            }

            $dbh->do(qq{
                INSERT INTO plugin_recalls ( issue_id, reserve_id, rule ) VALUES ( ?, ?, ? );
            }, undef, ( $checkout->id, $hold->id, YAML::Dump($rule) ) );

            my $letter = C4::Letters::GetPreparedLetter(
                module      => 'reserves',
                letter_code => 'RECALL_PLUGIN',
                branchcode  => $hold->branchcode,
                lang        => $patron->lang,
                tables      => {
                    branches  => $checkout->branchcode,
                    borrowers => $patron->id,
                    biblio    => $item->biblio->id,
                    items     => $item->id,
                    issues    => $item->id,
                },
                substitute => {
                    rule => $rule,
                },
            );
            if ($letter) {
                C4::Letters::EnqueueLetter(
                    {
                        letter         => $letter,
                        borrowernumber => $patron->id,
                        message_transport_type => 'email',
                    }
                ) or $data->{warning} = 'Unable to send email to current borrower';
            }

            $data->{success} = 1;
        }
        else {
            $data->{success} = 0;
        }
    }

    print $cgi->header(
        {
            -type     => 'text/json',
            -charset  => 'UTF-8',
            -encoding => "UTF-8"
        }
    );
    print to_json($data);
}

sub cronjob_nightly {
    my ( $self, $args ) = @_;

    my $dbh = C4::Context->dbh;

    my $recalls = $dbh->selectall_arrayref(
        'SELECT * FROM plugin_recalls WHERE issue_id IS NOT NULL',
        { Slice => {} } );

    foreach my $r ( @$recalls ) {
        my $checkout = Koha::Checkouts->find( $r->{issue_id} );
        if ( $checkout->is_overdue ) {
            my $rule = YAML::Load( $r->{rule} );

            if ( $rule->{past_due_restrict} ) {
                my $title = $checkout->item->biblio->title;
                my $barcode = $checkout->item->barcode;
                my $date_due_formatted = Koha::DateUtils::format_sqldatetime( $checkout->date_due );

                my $comment = "Patron restricted for failing to return recalled item in time: $title ( $barcode ) Due $date_due_formatted";

                my $restrictions = Koha::Patron::Debarments::GetDebarments( { borrowernumber => $checkout->patron->id, comment => $comment } );
                unless (@$restrictions) {
                    Koha::Patron::Debarments::AddDebarment(
                        {
                            borrowernumber => $checkout->patron->id,
                            type => 'MANUAL',
                            comment => $comment,
                        }
                    );
                }
            }

            if ( $rule->{past_due_fine_amount} ) {
                my $barcode = $checkout->item->barcode;
                my $date_due_formatted = Koha::DateUtils::format_sqldatetime( $checkout->date_due );

                my $description = "Failure to return recalled item in time: ( $barcode ) Due $date_due_formatted";

                my $recalls = $dbh->selectall_arrayref(
                    'SELECT * FROM accountlines WHERE borrowernumber = ? AND itemnumber = ? AND description = ? AND accounttype = ?',
                    { Slice => {} }, $checkout->patron->id, $checkout->item->id, $description, 'F' );
                unless ( @$recalls ) {
                    C4::Accounts::manualinvoice( $checkout->patron->id, $checkout->item->id, $description, 'F', $rule->{past_due_fine_amount} );
                }
            }
        }
    }
}

sub cronjob {
    my ( $self, $args ) = @_;

    my $dbh = C4::Context->dbh;

    my $recalls = $dbh->selectall_arrayref(
        'SELECT * FROM plugin_recalls WHERE issue_id IS NULL',
        { Slice => {} } );

    for my $r ( @$recalls ) {
        my $hold = Koha::Holds->find( $r->{reserve_id} );

        next if $hold->notificationdate;

        my $rule = YAML::Load( $r->{rule} );

        my $expirationdate = dt_from_string( $hold->waitingdate )->add( days => $rule->{pickup_date_length} );
        $hold->expirationdate( $expirationdate );
        $hold->notificationdate( dt_from_string() );
        $hold->store();

        my @messages = Koha::Notice::Messages->search(
            {
                borrowernumber => $hold->borrowernumber,
                letter_code    => 'HOLD',
                status         => 'pending',
                content        => { like => "%ID: $r->{reserve_id}.%\r\n" },
            }
        );

        my $patron = Koha::Patrons->find( $hold->borrowernumber );
        my $library = Koha::Libraries->find( $hold->branchcode );
        my $letter = C4::Letters::GetPreparedLetter(
            module      => 'reserves',
            letter_code => 'RECALL_PICKUP_PLUGIN',
            branchcode  => $hold->branchcode,
            lang        => $patron->lang,
            tables      => {
                'branches'    => $library->unblessed,
                'borrowers'   => $patron->unblessed,
                'biblio'      => $hold->biblionumber,
                'biblioitems' => $hold->biblionumber,
                'reserves'    => $hold->unblessed,
                'items'       => $hold->itemnumber,
            },
            substitute => {
                rule => $rule,
            },
        );

        if ($letter) {
            my $id = C4::Letters::EnqueueLetter(
                {
                    letter         => $letter,
                    borrowernumber => $patron->id,
                    message_transport_type => 'email',
                }
            );

            if ($id) {    # Delete hold waiting notices
                $_->delete() for @messages;
            }
        }
    }
}

## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;

    my $dbh = C4::Context->dbh;

    $dbh->do(qq{
        CREATE TABLE IF NOT EXISTS `plugin_recalls` (
          `issue_id` INT(11) NULL,
          `reserve_id` INT(11) NOT NULL,
          `rule` TINYTEXT NOT NULL,
          KEY `issue_id` (`issue_id`),
          KEY `reserve_id` (`reserve_id`),
          CONSTRAINT `plugin_recalls_ibfk_2` FOREIGN KEY (`reserve_id`) REFERENCES `reserves` (`reserve_id`) ON DELETE CASCADE ON UPDATE CASCADE,
          CONSTRAINT `plugin_recalls_ibfk_1` FOREIGN KEY (`issue_id`) REFERENCES `issues` (`issue_id`) ON DELETE SET NULL ON UPDATE CASCADE
        ) ENGINE=InnoDB;
    });

    $dbh->do(q{
        INSERT IGNORE INTO `letter` (`module`, `code`, `branchcode`, `name`, `is_html`, `title`, `content`, `message_transport_type`, `lang`)
        VALUES
            ('reserves', 'RECALL_PLUGIN', '', 'Recall Notice for Recalls Plugin', 0, 'An item you have checked out has been recalled', '[%- USE KohaDates -%]\r\n[%- USE Price -%]\r\nDate: <<today>>\r\n\r\nA recall has been placed on the following item: [% biblio.title %] / [% biblio.author %] ( [% item.barcode %] ).\r\nThe due date has been updated, and is now [% checkout.date_due | $KohaDates %].\r\nPlease return the item before the due date.\r\n\r\n[%- IF rule.past_due_fine_amount %]\r\n  If you fail to do so, you will be charged a fee of $[% rule.past_due_fine_amount | $Price %]\r\n[%- END %]\r\n[%- IF rule.past_due_restrict %]\r\n  If you fail to do so, you will be restricted from checking out new items.\r\n[%- END %]', 'email', 'default'),
            ('reserves', 'RECALL_PICKUP_PLUGIN', '', 'Recalled item ready for pickup', 0, 'Recalled item ready for pickup', 'Dear <<borrowers.firstname>> <<borrowers.surname>>,\r\n\r\nYou have a recall available for pickup as of <<reserves.waitingdate>>:\r\n\r\nTitle: <<biblio.title>>\r\nAuthor: <<biblio.author>>\r\nCopy: <<items.copynumber>>\r\nLocation: <<branches.branchname>>\r\n<<branches.branchaddress1>>\r\n<<branches.branchaddress2>>\r\n<<branches.branchaddress3>>\r\n<<branches.branchcity>> <<branches.branchzip>>\r\n', 'email', 'default');
    });

    return 1;
}

sub update_syspref {
    my ($self, $syspref_name, $data) = @_;

    my $name = $self->get_metadata->{name};

    my $syspref = C4::Context->preference($syspref_name);
    $syspref =~ s|\n*/\* JS and CSS for $name Plugin.*End of JS and CSS for $name Plugin \*/||gs;

    my $template = $self->get_template( { file => "$syspref_name.tt" } );
    $template->param(%$data);

    my $template_output = $template->output();

    $template_output = qq|\n/* JS and CSS for $name Plugin 
   This JS was added automatically by installing the $name Plugin
   Please do not modify */|
      . $template_output
      . qq|/* End of JS and CSS for $name Plugin */|;

    $syspref .= $template_output;
    C4::Context->set_preference( $syspref_name, $syspref );
}

## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
sub uninstall() {
    my ( $self, $args ) = @_;
}

1;
