use utf8;
use diagnostics;
use strict;
use warnings;
use Time::Local;

# special thanks to:
# http://perlmeme.org/howtos/subroutines/perl_files.html

sub timestamp_to_gmtime_dst {
    my ($timestamp) = @_;
    # fetch daylight savings time flag (0 or 1)
    my $dst = (localtime($timestamp))[8];
    # format string to UTC like before
    my $timestr = strftime("%Y-%m-%dT%H:%M:%SZ", $timestamp);
    # persist current machine's DST information in non-standard time string
    return sprintf("%sDST%s", $timestr, $dst);
}

sub tz_is_dst_eligible {
    # some states do not use DST (Hawaii, Arizona, etc.)
    # use Jun 1 2020 as an arbitrary date to check DST of the locale
    # (DST always runs between first Sun of Mar and first Sun of Nov)
    my $timestamp_dst_day = 1590984000;
    # fetch daylight savings time flag (0 or 1)
    my $dst_flag_then = (localtime($timestamp_dst_day))[8];
    return $dst_flag_then;
}

sub dst_offset_compare {
    my ($dst_then, $dst_now) = @_;
    
    # Just as Perl sets %z it based on the system, not $timestamp,
    # Logic Pro X also seems to use the current locale's system for %z
    # instead of checking the actual GMT offset on the date being considered.
    #
    # As a result of this undocumented FEATURE, when Logic X checks if the files
    # are modified or not it can be thrown off +/- one hour (3600 secs). Artifically
    # adjust the modified date time on the FILESYSTEM when applying metadata
    # to trick Logic X to chill.
    
    
    if (!tz_is_dst_eligible()) {
        # this hack only is required for locales that use DST
        return 0;
    }
    
    if ($dst_then && !$dst_now) {
        # artificially "spring forward" when setting the timestamp
        return 1;
    } elsif (!$dst_then && $dst_now) {
        # artificially "fall back" when setting the timestamp
        return -1;
    } else {
        return 0;
    }
}

sub gmtime_to_timestamp_dst {
    my ($gmtime) = @_;
    $gmtime =~ m/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z(DST(\d{1}))?$/;
    my $timestamp_utc = timegm($6, $5, $4, $3, $2 - 1, $1);
    my $dst_flag = $8;
    my $dst_now = (localtime)[8];
    return $timestamp_utc + 3600 * dst_offset_compare($dst_flag, $dst_now);
}

1;
