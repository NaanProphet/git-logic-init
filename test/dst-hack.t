use diagnostics;
use warnings;
use strict;
use Test::More qw( no_plan );
use POSIX qw( tzset );
use Time::Local;
use Term::ANSIColor;

# use relative module for less deps
use MockTime;

# To run tests, simply run `perl dst-hack.t` FROM this folder

# special thanks to:
# http://www.jmdeldin.com/bioinf/testing/index.html
# https://en.wikipedia.org/wiki/List_of_tz_database_time_zones

do '../scripts/dst-hack.pl';

## ---------------------
## dst_offset_compare($dst_then, $dst_now)
## ---------------------
$ENV{TZ} = 'America/New_York';
print colored( sprintf("given locale where daylight savings is observed ($ENV{TZ}) - Eastern Time"), 'magenta' ), "\n";
is(dst_offset_compare(1,0), 1, 'if file was saved when DST was (on) and DST is (off) now, then adjust forward by 1 hour');
is(dst_offset_compare(1,1), 0, 'if file was saved when DST was (on) and DST is (on) now, then do not adjust anything');
is(dst_offset_compare(0,0), 0, 'if file was saved when DST was (off) and DST is (off) now, then do not adjust anything');
is(dst_offset_compare(0,1), -1, 'if file was saved when DST was (off) and DST is (on) now, then adjust backward by 1 hour');
$ENV{TZ} = 'America/Chicago';
print colored( sprintf("given locale where daylight savings is observed ($ENV{TZ}) - Central Time"), 'magenta' ), "\n";
is(dst_offset_compare(1,0), 1, 'if file was saved when DST was (on) and DST is (off) now, then adjust forward by 1 hour');
is(dst_offset_compare(1,1), 0, 'if file was saved when DST was (on) and DST is (on) now, then do not adjust anything');
is(dst_offset_compare(0,0), 0, 'if file was saved when DST was (off) and DST is (off) now, then do not adjust anything');
is(dst_offset_compare(0,1), -1, 'if file was saved when DST was (off) and DST is (on) now, then adjust backward by 1 hour');
$ENV{TZ} = 'America/Phoenix';
print colored( sprintf("given locale where daylight savings is NOT observed ($ENV{TZ}) - Mountain Time"), 'magenta' ), "\n";
is(dst_offset_compare(1,0), 0, 'if file was saved when DST was (on) and DST is (off) now, then do not adjust anything');
is(dst_offset_compare(1,1), 0, 'if file was saved when DST was (on) and DST is (on) now, then do not adjust anything');
is(dst_offset_compare(0,0), 0, 'if file was saved when DST was (off) and DST is (off) now, then do not adjust anything');
is(dst_offset_compare(0,1), 0, 'if file was saved when DST was (off) and DST is (on) now, then do not adjust anything');
$ENV{TZ} = 'America/Denver';
print colored( sprintf("given locale where daylight savings is observed ($ENV{TZ}) - Mountain Time"), 'magenta' ), "\n";
is(dst_offset_compare(1,0), 1, 'if file was saved when DST was (on) and DST is (off) now, then adjust forward by 1 hour');
is(dst_offset_compare(1,1), 0, 'if file was saved when DST was (on) and DST is (on) now, then do not adjust anything');
is(dst_offset_compare(0,0), 0, 'if file was saved when DST was (off) and DST is (off) now, then do not adjust anything');
is(dst_offset_compare(0,1), -1, 'if file was saved when DST was (off) and DST is (on) now, then adjust backward by 1 hour');
$ENV{TZ} = 'Pacific/Honolulu';
print colored( sprintf("given locale where daylight savings is NOT observed ($ENV{TZ}) - Aleutian Time"), 'magenta' ), "\n";
is(dst_offset_compare(1,0), 0, 'if file was saved when DST was (on) and DST is (off) now, then do not adjust anything');
is(dst_offset_compare(1,1), 0, 'if file was saved when DST was (on) and DST is (on) now, then do not adjust anything');
is(dst_offset_compare(0,0), 0, 'if file was saved when DST was (off) and DST is (off) now, then do not adjust anything');
is(dst_offset_compare(0,1), 0, 'if file was saved when DST was (off) and DST is (on) now, then do not adjust anything');

## ---------------------
## gmtime_to_timestamp_dst($gmtime)
## ---------------------
print colored( sprintf("regex checks YYYY-MM-DDTHH:MM:SSZDST[0/1]"), 'magenta' ), "\n";
my $gmtime_string = '2019-10-01T10:19:58ZDST1';
ok(gmtime_to_timestamp_dst($gmtime_string), "regex passes for custom DST timestring ($gmtime_string)");
$gmtime_string = '2019-10-01T10:19:58ZDST0';
ok(gmtime_to_timestamp_dst($gmtime_string), "regex passes for custom DST timestring ($gmtime_string)");
$gmtime_string = '2019-10-01T10:19:58Z';
ok(gmtime_to_timestamp_dst($gmtime_string), "backwards compatibility - regex passes for legit GMT timestring ($gmtime_string)");
is(gmtime_to_timestamp_dst($gmtime_string), 1569925198, "backwards compatibility - no offset assumed when DST regex is missing");
$gmtime_string = undef;

## ---------------------
## "integration" tests
## ---------------------

my $then_string = '2019-10-01T10:19:58ZDST1';
my $then_millis = 1569925198;
Test::MockTime::set_absolute_time('2020-12-01T05:00:00Z');
my $now_string = localtime;
print colored( sprintf("mock localdate set to DST off (%s), file originally saved when DST on (%s)", $now_string, $then_string), 'magenta' ), "\n";
$ENV{TZ} = 'America/Phoenix';
is(gmtime_to_timestamp_dst($then_string), $then_millis, 'ignore artificial DST offset for (Arizona) a place that does not have daylight savings');
$ENV{TZ} = 'Pacific/Honolulu';
is(gmtime_to_timestamp_dst($then_string), $then_millis, 'ignore artificial DST offset for (Hawaii) a place that does not have daylight savings');
$ENV{TZ} = 'America/New_York';
is(gmtime_to_timestamp_dst($then_string), $then_millis+3600, 'file artifically offset +1 hour for (New York) a place that does have daylight savings');
$ENV{TZ} = 'America/Chicago';
is(gmtime_to_timestamp_dst($then_string), $then_millis+3600, 'file artifically offset +1 hour for (Chicago) a place that does have daylight savings');
$now_string = undef;
# same $then_string as before
Test::MockTime::set_absolute_time('2021-06-01T05:00:00Z');
$now_string = localtime;
print colored( sprintf("mock localdate set to DST on (%s), file originally saved when DST on (%s)", $now_string, $then_string), 'magenta' ), "\n";
$ENV{TZ} = 'America/Phoenix';
is(gmtime_to_timestamp_dst($then_string), $then_millis, 'ignore artificial DST offset for (Arizona) a place that does not have daylight savings');
$ENV{TZ} = 'Pacific/Honolulu';
is(gmtime_to_timestamp_dst($then_string), $then_millis, 'ignore artificial DST offset for (Hawaii) a place that does not have daylight savings');
$ENV{TZ} = 'America/New_York';
is(gmtime_to_timestamp_dst($then_string), $then_millis, 'no offset when DST is on again for (New York) a place that does have daylight savings');
$ENV{TZ} = 'America/Chicago';
is(gmtime_to_timestamp_dst($then_string), $then_millis, 'no offset when DST is on again for (Chicago) a place that does have daylight savings');
$now_string = undef;
$then_string = undef;
$then_millis = undef;



$then_string = '2019-11-03T15:31:01ZDST0';
$then_millis = 1572795061;
Test::MockTime::set_absolute_time('2020-12-01T05:00:00Z');
$now_string = localtime;
print colored( sprintf("mock localdate set to DST off (%s), file originally saved when DST off (%s)", $now_string, $then_string), 'magenta' ), "\n";
$ENV{TZ} = 'America/Phoenix';
is(gmtime_to_timestamp_dst($then_string), $then_millis, 'ignore artificial DST offset for (Arizona) a place that does not have daylight savings');
$ENV{TZ} = 'Pacific/Honolulu';
is(gmtime_to_timestamp_dst($then_string), $then_millis, 'ignore artificial DST offset for (Hawaii) a place that does not have daylight savings');
$ENV{TZ} = 'America/New_York';
is(gmtime_to_timestamp_dst($then_string), $then_millis, 'no offset when DST is off then and now for (New York) a place that does have daylight savings');
$ENV{TZ} = 'America/Chicago';
is(gmtime_to_timestamp_dst($then_string), $then_millis, 'no offset when DST if off then and now for (Chicago) a place that does have daylight savings');
$now_string = undef;
# same $then_string as before
Test::MockTime::set_absolute_time('2021-06-01T05:00:00Z');
$now_string = localtime;
print colored( sprintf("mock localdate set to DST on (%s), file originally saved when DST off (%s)", $now_string, $then_string), 'magenta' ), "\n";
$ENV{TZ} = 'America/Phoenix';
is(gmtime_to_timestamp_dst($then_string), $then_millis, 'ignore artificial DST offset for (Arizona) a place that does not have daylight savings');
$ENV{TZ} = 'Pacific/Honolulu';
is(gmtime_to_timestamp_dst($then_string), $then_millis, 'ignore artificial DST offset for (Hawaii) a place that does not have daylight savings');
$ENV{TZ} = 'America/New_York';
is(gmtime_to_timestamp_dst($then_string), $then_millis-3600, 'file artifically offset -1 hour for (New York) a place that does have daylight savings');
$ENV{TZ} = 'America/Chicago';
is(gmtime_to_timestamp_dst($then_string), $then_millis-3600, 'file artifically offset -1 hour for (Chicago) a place that does have daylight savings');
$now_string = undef;
$then_string = undef;
$then_millis = undef;

