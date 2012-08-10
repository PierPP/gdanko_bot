#!/usr/bin/perl

use strict;
use DBI;

my $dbh = DBI->connect("dbi:SQLite:dbname=/home/gdanko/bot/bot.db", "", "");
$dbh->do("DROP TABLE IF EXISTS users");
$dbh->do("CREATE TABLE users (nick TEXT UNIQUE, mask TEXT, password TEXT NOT NULL, level INTEGER NOT NULL, last_auth INTEGER DEFAULT 0, bad_attempts INTEGER DEFAULT 0, locked INTEGER NOT NULL DEFAULT 0)");

$dbh->do("DROP TABLE IF EXISTS devices");
$dbh->do("CREATE TABLE devices (id TEXT UNIQUE, description TEXT, nick TEXT)");

$dbh->do("DROP TABLE IF EXISTS seen");
$dbh->do("CREATE TABLE seen (nick TEXT NOT NULL, time INTEGER NOT NULL, channel NOT NULL)");

$dbh->do("DROP TABLE IF EXISTS links");
$dbh->do("CREATE TABLE links (title TEXT NOT NULL, url TEXT NOT NULL, nick TEXT)");
