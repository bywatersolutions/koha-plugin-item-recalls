# Koha Item Recalls plugin

This Koha plugin that adds the ability to place recalls on items.

# Introduction

Koha’s Plugin System (available in Koha 3.12+) allows for you to add additional tools and reports to [Koha](http://koha-community.org) that are specific to your library. Plugins are installed by uploading KPZ ( Koha Plugin Zip ) packages. A KPZ file is just a zip file containing the perl files, template files, and any other files necessary to make the plugin work. Learn more about the Koha Plugin System in the [Koha 3.22 Manual](http://manual.koha-community.org/3.22/en/pluginsystem.html) or watch [Kyle’s tutorial video](http://bywatersolutions.com/2013/01/23/koha-plugin-system-coming-soon/).

# Downloading

From the [release page](https://github.com/bywatersolutions/koha-plugin-item-recalls/releases) you can download the relevant *.kpz file

# Installing

Koha's Plugin System allows for you to add additional tools and reports to Koha that are specific to your library. Plugins are installed by uploading KPZ ( Koha Plugin Zip ) packages. A KPZ file is just a zip file containing the perl files, template files, and any other files necessary to make the plugin work.

The plugin system needs to be turned on by a system administrator.

To set up the Koha plugin system you must first make some changes to your install.

* Change `<enable_plugins>0<enable_plugins>` to `<enable_plugins>1</enable_plugins>` in your koha-conf.xml file
* Confirm that the path to `<pluginsdir>` exists, is correct, and is writable by the web server
* Restart your webserver
* Restart memcached if you are using it

Once set up is complete you will need to alter your UseKohaPlugins system preference. On the Tools page you will see the Tools Plugins and on the Reports page you will see the Reports Plugins.

# Setup

* Install the plugin
* Ensure each HOLD notice ends with the following code:

```
--
ID: <<reserves.reserve_id>>.
--
```

* Add the following to each staff and opac section of your Apache config:

```apache
Alias /plugin "/var/lib/koha/kohadev/plugins"
# The stanza below is needed for Apache 2.4+
<Directory /var/lib/koha/kohadev/plugins>
      Options Indexes FollowSymLinks ExecCGI
      AddHandler cgi-script .pl
      AllowOverride None
      Require all granted
</Directory>
```

* Set up the nightly cronjob
* Tie the regular cronjob to the cronjob for process_message_queue.pl so it always run before it


# Staff Client Setup

When you install the plug in, it does three things:
Creates a table called Plug_In_recalls - has added Reserve ID and the item number
Creates two new notices: RECALL_Plugin and RECALL_pickup
Goes through the Holds notices and adds the Reserve ID.


# For Recalls to Happen: 
Item must be checked out
Item must be on hold
For a patron to place a recall on the hold- they need to be the first person on hold and the hold must be an item level hold.
Must have a rule allowing item recall

To configure rules for the ability to recall the holds- Manage Plugins, Configure “Recall Holds Plugin”


These rules are written in YAML which when you create a rule, verify at YAMLit.com that code is correct

BC= branch code - currently is the pick up location
CC= category code - patron type from authorized values


Rules are checked top to bottom - matches on the first matching rule it finds, so have the rules most specific to least specific.

Due_date_length = how many days from today the current patron  has to return the item.  Example: 3 means you have 3 days to return the item.
Past_due_fine_amount = Optional charge for patrons who fail to return a recall by the new due date.  This is an addition to any other fines that accrue.
Past_due_restrict = Optional ability to restrict a patron who fails to return a recall by the new due date.
Example 0=no restriction 1 = restrict
Pickup_date_length = Number of days the recaller has to pick up the now awaiting item. 

If you take out the branch code, category code and item code, the rules will apply to all locations, all patron types, and all item types.

Since these rules allow for specific branch codes, patron types and Items to be recalled- each combination of these would have their own set up rules configured in the plugin.


This recall can be done on both the staff side and the OPAC


# Steps to recreate this from Staff Side.  
1. Find an item that is currently checked out.
2. Go to place a hold on this item.  This must be an item level hold- so pick the specific copy that is checked out.
3.Once the hold is created, this screen (see above) will appear.
4.Within a sec, the recall item symbol resembles the refresh icon in browsers will appear.  
5.Click this recall symbol - the staff will see a pop up message that says that the item has been recalled.
6.A notice will go to the patron that currently has the booked checked out.  
7.  The language can be adjusted for this recall notice in the Notices and Slips .
8.  The due date changes on the patrons account that has the book.
9.  Once the item has been returned to the library- the patron that was first on the list and that chose for the recall will be notified that their hold is available.  
10.  The cron will change the notice from the standard “Hold Available for Pickup” to the Recall Hold notice - due to the fact that they will have a limited number of days to pick up the item they recalled.



# Steps for recalling holds on the OPAC

1.Patron would log into their account on the OPAC.
2.Find a book that is currently checked out.
3.Place a hold on this book.  This does need to be a specific item hold, the patron would need to choose “show more options” which would allow them to choose a specific item
4.Koha will display the patrons holds on the patron summary screen and there will be an orange button that displays to “recall the hold”
5.  Clicking to recall the item does create a popup saying that the item has been recalled.
6. The due date for the patron that has it currently checked out will be adjusted per the rules set up in the plugin configuration.
7. Steps are the same for Staff and OPAC from here.



# Things to Note


Cron job needs to be set to run for this before the holds notices are run, as this cron job will change a hold pickup notice to Item Recall Pickup notice

ID378 -  this little line of info at the bottom of the notice is very important (the number will change).  This is the Hold ID, or Reserve ID.

