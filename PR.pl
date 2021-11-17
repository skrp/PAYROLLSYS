#!/bin/perl
use PDF::API2;
use File::Copy;
###################################
# PR - payroll computation system
###################################
use strict; use warnings;
use File::Copy;
# DATA STRUCT #####################
my ($input) = @ARGV;
die "ARG1 input-file\n" unless (defined $input);
# main data struct
my %stub; # hash of array of hash
# secondary struct
my %ee; # hash of hash
my %hr; # hash of hash
# support struct
my @taxtable; # array of array of array
my %VAR; # hash 
# GLOBALS #########################
my ($company, $date, $year);
my $ROW = 0; 	# PR row 
my $y_ROW = 0; 	# YTD row
my $dir_ee = 'ee/'; # dir ee data
my $dir_tables = 'tables/'; # work files
my $dir_pay = 'ytd/'; # dir per payroll
my $dir_last = 'last/'; # ee last paid stub
# tax tables
loadcsv();
# annual limits
my @var = slurp($dir_tables.'var.txt');
for (@var)
{
	my @ii_var = split(":",$_);
	$ii_var[1] = 0 if (!$ii_var[1]);
	$VAR{$ii_var[0]} = $ii_var[1];
}
my @STUB_COL = slurp($dir_tables.'stub_col.txt');
# RUN #############################
in_txt();
load_ee();
load_last();
prcalc();
col_sum();
# Point of No Return make changes to files
#my $bkup = $dir_pay.$$."old.tar";
#`tar -cf $bkup $dir_last`;
newstub();
# INPUT ###########################
sub in_txt
{
	my @in_file = slurp($input);
# set global variables & check year against var.txt
	($company,$date)=split(" ", shift @in_file);
	chomp $company; chomp $date;
	$date =~ s%/%_%g;
# setup payroll dir
	$dir_pay .= $date;
	$dir_pay .= "/";
	$year = substr($date,5);
# sanitize input
	die "FAIL year $year\n" unless (length($year) == 4);
	die "FAIL var.txt year $VAR{year} $year\n" unless ($VAR{year} == $year);
	die "FAIL company $company\n" unless ($company eq $VAR{company});
# rm col headers
	shift @in_file;
# populate %ee %hr
	for (@in_file)
	{
		my $emp;
# tab delimit text file
		my @i = split("\t", $_);
		next if (@i < 2);
		$emp = $i[0];
# check name
		next unless ($emp =~ m%_%);
# set hours owed in %hr
		$hr{$emp}{salary}=$i[1];
		$hr{$emp}{reg}=$i[2];
		$hr{$emp}{pto}=$i[3];
		$hr{$emp}{ot}=$i[4];
		$hr{$emp}{flat}=$i[6];
		#next if (($i[1]+$i[2]+$i[3]+$i[4]+$i[6]) == 0);
# populate %ee
		$ee{$emp} = undef;
	}
}
###################################
sub load_ee
{
# load ee files  from ee dir ######
        foreach my $emp (keys %ee)
        {
		my $ifile = $dir_ee.$emp.'.txt';
		die "FAIL ee file $emp\n" unless (-f $ifile);
                my @i_ee = slurp($ifile);
# evolve ee into hash of hashes ###
                for (@i_ee)
               {
		       next unless m/:/;
                        my @ii_ee = split(":",$_);
                        $ii_ee[1] = 0 if (!$ii_ee[1]);
                        $ee{$emp}{$ii_ee[0]} = $ii_ee[1];
 	       }
	}
}
# load stubs from last dir #####
sub load_last
{ # load company ytd
	my $iy = $dir_last.'ytd.txt';
	if (-f $iy)
	{ 
		stubload('ytd',$iy); 
		print "$company $dir_pay\trow: $ROW ttl: $y_ROW\n";
	}
# first payroll year
	else 
	{
		$ROW = 0; $y_ROW = 1;
		($stub{ytd}[$y_ROW]{$_}=0) for (@STUB_COL);
		print "FIRST $company $dir_pay\trow: $ROW ttl: $y_ROW\n";
	}
# load emp payroll data 
        foreach my $emp (keys %ee)
        {
                my $lfh;
                my $last = $dir_last.$emp.'.txt';
		if (-f $last) 
		{
			my $rowcnt = stubload($emp,$last);
			zeroout($emp, $rowcnt);
		}
		else 
# zero ytd for first employee payroll
		{
			zeroout($emp, 0);
			#	($stub{$emp}[$y_ROW]{$_}=0) for (@STUB_COL);
		}
	}
}
sub stubload
{
        my ($i,$last) = @_;
        my @i_last = slurp($last);
# old_ytd
        my @iycol = split("\t",pop(@i_last));
# create stub matrix
        my @row = 0..@i_last; pop @row;
	my $irow = 0;
        for (@row)
        {
# array of enteries per row
                my @i_col = split("\t",$i_last[$irow]);
# populate array of hash cell by cell
                my $i_pos = 0;
                foreach my $col (@STUB_COL)
                        {$stub{$i}[$irow]{$col} = $i_col[$i_pos++];}
		$irow++;
        } # $irow now equals last paid payroll 
        my $y_entry=0;
        my $yrow = $irow+1;
# ytd will have all payrolls & able to set GLOBAL
	if ($i eq 'ytd')
		{ $ROW = $irow; $y_ROW = $yrow; }
# company ytd stub will set $y_ROW GLOBAL
        foreach my $col (@STUB_COL)
                {$stub{$i}[$y_ROW]{$col} = $iycol[$y_entry++];}
        return $yrow;
}
sub zeroout
{ # zero non
	my ($emp, $irowcnt) = @_;
	$irowcnt-- if ($irowcnt > 0); # set to current row
	while ($irowcnt < $ROW)
	{
		for (@STUB_COL)
			{$stub{$emp}[$irowcnt]{$_} = 0;}
		$irowcnt++;
	}
}
sub col_sum
{
	foreach my $emp (keys %ee)
	{
		my @istub = @STUB_COL; 
		shift @istub;

		foreach my $icol (@istub)
		{
			$stub{$emp}[$y_ROW]{$icol} = 0;
			for (my $irow = 0; $irow < $y_ROW; $irow++)
			{ 
				if (defined $stub{$emp}[$irow]{$icol}) 
					{$stub{$emp}[$y_ROW]{$icol} += $stub{$emp}[$irow]{$icol};}
				else {print "FAIL col_sum $emp $irow $icol\n";}
			}
		}
	}
}
sub ytd
{ # each payroll employee will append own & company totals
	foreach my $emp (keys %ee)
	{
		my @istub = @STUB_COL; 
# set date manual
		shift @istub;

		foreach my $icol (@istub)
		{ 
			$stub{$emp}[$y_ROW]{$icol} += $stub{$emp}[$ROW]{$icol};
# payroll total = ROW
			$stub{ytd}[$ROW]{$icol} += $stub{$emp}[$ROW]{$icol};
# year-to-date total = y_ROW
			$stub{ytd}[$y_ROW]{$icol} += $stub{$emp}[$ROW]{$icol};
		}
		$stub{$emp}[$y_ROW]{date} = "YTD";
	}
# YTD date set
	$stub{ytd}[$ROW]{date} = $date;
	$stub{ytd}[$y_ROW]{date} = "YTD";
}
sub newstub 
{ # company ytd
        my $ylast = $dir_last.'ytd.txt';
        my $ycur = $dir_pay.'ytd.txt';
	stub($ylast,$ycur,'ytd');
	stubpdf($ylast,$ycur,'ytd');
# new last & current stubs
	foreach my $emp (keys %ee)
	{# print rows of pr array
                my $ilast = $dir_last.$emp.'.txt';
                my $icur = $dir_pay.$emp.'.txt';
		stub($ilast,$icur,$emp);
		stubpdf($icur,$emp);
	}
}
sub stub
{
	my ($ilast,$icur, $emp) = @_;
# remove old last file
	unlink $ilast;
	open(my $lfh, '>>', $ilast) or die "FAIL new_last $emp $!\n";
# populate stub 
	my @irow=0..$y_ROW; # pop @irow;
	foreach my $irow (@irow)
	{
		foreach my $icol (@STUB_COL)
#	{ print $lfh "$stub{$emp}[$irow]{$icol}\t" || print $lfh "0\t"; }
		{ 
			if (defined $stub{$emp}[$irow]{$icol})
				{ print $lfh "$stub{$emp}[$irow]{$icol}\t"; }
			else
				{ print $lfh "0\t"; }
		}
		print $lfh "\n";
	}
	close $lfh;
	copy($ilast, $icur) or die "FAIL last2current $emp $!\n";
}
###################################
sub prcalc
{
# create dir payroll stubs # if (!-d $dir_pay)
# will die if attempt to overwrite pr -> each pr needs unique date dir
	mkdir $dir_pay or die "FAIL mkdir $dir_pay $!\n";
# calculate payroll in %pr ########
	foreach my $emp (keys %ee)
	{
		$stub{$emp}[$ROW]{date} = $date;
# GROSS ###########################
		$stub{$emp}[$ROW]{salary} = $ee{$emp}{rate}; 
		$stub{$emp}[$ROW]{salary} = $hr{$emp}{salary}; 
		$stub{$emp}[$ROW]{salary} =~ s/\$//; # remove '$' from Salary 
		
		$stub{$emp}[$ROW]{reg} = sprintf("%.2f", ($hr{$emp}{reg} * $ee{$emp}{rate}));
		
		my $ipto = ratio($ee{$emp}{pto}, $hr{$emp}{pto}, $stub{$emp}[$y_ROW]{pto});
		$stub{$emp}[$ROW]{pto} = sprintf("%.2f", ($ipto * $ee{$emp}{rate})); 

		$stub{$emp}[$ROW]{ot} = sprintf("%.2f", ($hr{$emp}{ot} * $ee{$emp}{ot})); 

		$stub{$emp}[$ROW]{flat} = $hr{$emp}{flat}; 
		$stub{$emp}[$ROW]{flat} =~ s/\$//; # remove '$' from Flat Pay

# gross
		my $igross = $stub{$emp}[$ROW]{reg};
	 	$igross += $stub{$emp}[$ROW]{salary};
	 	$igross += $stub{$emp}[$ROW]{pto};
		$igross += $stub{$emp}[$ROW]{ot};
		$igross += $stub{$emp}[$ROW]{flat};
		$stub{$emp}[$ROW]{gross} = sprintf("%.2f", $igross); 
# DED #############################
		$stub{$emp}[$ROW]{garnish} = sprintf("%.2f",($ee{$emp}{garnishrate}*$stub{$emp}[$ROW]{gross}));
		$stub{$emp}[$ROW]{garnish} += $ee{$emp}{garnishamt};
		if ($stub{$emp}[$ROW]{garnish} > $stub{$emp}[$ROW]{gross})
			{$stub{$emp}[$ROW]{garnish} = 0;}

		$stub{$emp}[$ROW]{loan} = sprintf("%.2f", ratio($ee{$emp}{loanmax}, $ee{$emp}{loanamt}, $stub{$emp}[$y_ROW]{loan}));

		$stub{$emp}[$ROW]{inshealth} = $ee{$emp}{inshealth};

		$stub{$emp}[$ROW]{insdental} = $ee{$emp}{insdental}; 

		$stub{$emp}[$ROW]{hsa} = $ee{$emp}{hsa}; 

		$stub{$emp}[$ROW]{pension} = pension($emp);
# TAX #############################
		# remove 401k from gross to calc fit
		$stub{$emp}[$ROW]{pre} = $stub{$emp}[$ROW]{gross}-$stub{$emp}[$ROW]{pension};

		my $i_ss = ratio($VAR{ss_max},$stub{$emp}[$ROW]{gross},$stub{$emp}[$y_ROW]{gross});
		$i_ss *= $VAR{ss_rate};
		$stub{$emp}[$ROW]{sosec} = sprintf("%.2f",$i_ss);

		$stub{$emp}[$ROW]{med} = sprintf("%.2f", ($stub{$emp}[$ROW]{gross}*$VAR{medrate}));
# status
		my @w4 = split("_",$ee{$emp}{w4}); # format {Status_Children_Elderly}
		my $istatus = $w4[0];

		$stub{$emp}[$ROW]{addmed} = addmed($emp, $istatus);

		my $pre_fed = fed_tax($emp, $stub{$emp}[$ROW]{pre}, $ROW, @w4); #Fed Inc Tax
		$pre_fed += $ee{$emp}{addamtfed};
		($pre_fed = 0) if ($pre_fed < 0);
		$stub{$emp}[$ROW]{fit} = sprintf("%.2f",$pre_fed);

		my $pre_state = state_tax($emp, $stub{$emp}[$ROW]{pre}, $istatus); #State Inc Tax
		$pre_state += $ee{$emp}{addamtstate};
		($pre_state = 0) if ($pre_state < 0);
		$stub{$emp}[$ROW]{sit} = sprintf("%.2f",$pre_state);
# NET #############################
		my $inet = $stub{$emp}[$ROW]{gross}
			-$stub{$emp}[$ROW]{garnish}-$stub{$emp}[$ROW]{loan}-$stub{$emp}[$ROW]{inshealth}
			-$stub{$emp}[$ROW]{insdental}-$stub{$emp}[$ROW]{hsa}-$stub{$emp}[$ROW]{pension}
			-$stub{$emp}[$ROW]{sosec}-$stub{$emp}[$ROW]{med}-$stub{$emp}[$ROW]{addmed}
			-$stub{$emp}[$ROW]{fit}-$stub{$emp}[$ROW]{sit};
		$stub{$emp}[$ROW]{net} = sprintf("%.2f",$inet);
	}
}
sub fed_tax
{ # federal income tax & addmed tax calculation
# page 51 of IRS-pub15-T Sect. 4 PMT
	my ($emp, $i_gross, $irow, @w4) = @_;
	my ($i_fedtax,$gross_itax);
	my $status = $w4[0];
	# adjustments to withholding done by ee-record addamtfed: $ee{$emp}[11] 
	# 	this is to get the min tax withholding
	# 	if spouse income greater use addamtfed in the ee file

	# 6 types of status: 
	# 	s - single
	# 	m - married
	# 	h- head of household
	# 	ss - single 2 jobs same pay
	# 	mm - married 2 jobs same pay (both spouses work)
	# 	hh - head 2 jobs same pay
# each status corresponds to a csv table see README
	if ($status eq 's') {$status = 2;}
	elsif ($status eq 'ss') {$status = 3;} 
	elsif ($status eq 'm') {$status = 0;}
	elsif ($status eq 'mm') {$status = 1;}
	elsif ($status eq 'h') {$status = 4;}
	elsif ($status eq 'hh') {$status = 5;}
	else { die "FAIL w4 status: $status\n";}
# Find floor amt which correspond to csv
  	my $w_cnt = 0; # Find floor amt which correspond to csv
  	while ($w_cnt < 8)
  	{
  		if (($taxtable[$status][$w_cnt][0] > $i_gross) || ($w_cnt == 7)) 
       		{ 
			my $floor = $taxtable[$status][--$w_cnt][0];
		
			my $base = $taxtable[$status][$w_cnt][2];
			my $perc = $taxtable[$status][$w_cnt][3];

			$perc = '.'.$perc;
			my $over = sprintf("%.2f",$i_gross - $floor);	
			my $perc_over = sprintf("%.2f",$perc*$over); 	
				
		       	$gross_itax = sprintf("%.2f",$base+$perc_over);

			last; 
		}
  		$w_cnt++;
 	}
	my $kid = 0;
	if ($w4[1] > 0) {my $ikid = ($w4[1]*2000)/$VAR{prtype}; $kid = sprintf("%.2f",$ikid);}

	my $depend = 0;
	if ($w4[2] > 0) {my $idepend = ($w4[2]*500)/$VAR{prtype}; $depend = sprintf("%.2f",$idepend);}

	$i_fedtax = sprintf("%.2f",($gross_itax - $kid - $depend));	
	return $i_fedtax;
}
sub state_tax
# entries corresp to utah state tax using pub 14 page 9
{ # use gross reduced by pension
	my ($emp, $igross, $i_status) = @_;
	my ($i_stax,$entry_2,$entry_3,$entry_4,$entry_5,$entry_6,$entry_7);

	$entry_2 = ($igross * .0495);

	if ($i_status eq 's' || $i_status eq 'ss')
	{
		$entry_3 = 14;
		$entry_4 = $igross - 274;
	}
	elsif ($i_status eq 'm' || $i_status eq 'mm' || $i_status eq 'h') 
	{
		$entry_3 = 28;
		$entry_4 = $igross - 548;
	}
	else { print "FAIL state tax status: $i_status $!\n"; } 
	($entry_4 = 0) if ($entry_4 < 0);

	$entry_5 = $entry_4*.013;
	$entry_6 = $entry_5 - $entry_3;
	($entry_6 = 0) if ($entry_6 < 0);
	$entry_7 = $entry_2 - $entry_6;
	($entry_7 = 0) if ($entry_7 < 0);
	
	$i_stax = sprintf("%.2f", $entry_7-$entry_3);

	return $i_stax;
}
sub slurp 
{
	my ($file) = @_;
	my $subfh; 
	my @slurp;

	open($subfh, '<', $file) or die "FAIL slurp $file : $!\n";
	@slurp = readline $subfh;
	close $subfh; chomp @slurp;

	return @slurp;
}
sub ratio
{
	my ($max, $amt, $ytd) = @_;
	if ($max > ($ytd + $amt)) 
		{return $amt;}
	elsif ($max < $ytd)
		{return 0;}
	else 	{return $max - $ytd;}
}
sub loadcsv 
{
	my $subfh; 
	my @slurp;
	my $b = 0;
	while ($b < 6)
	{ # ch $sf dir for different payroll types
	  my $sf = $dir_tables.'taxbiweek/'.$b.'.txt';
	  open($subfh, '<', $sf) or die "FAIL slurp $sf : $!\n";
	  my $bb=0;
	  while (<$subfh>) 
	  {
		chomp $_;
		my $line = $_;
		$line =~ s/\$//g;
		$line =~ s/\%//g;

		my @ia = split(',',$line);
		my $bbb = 0;
		for (@ia)
		{
		  $taxtable[$b][$bb][$bbb] = $_; 
		  $bbb++;
		}
		$bb++;
	  }
	  $b++;
	}
	return @slurp;
}
sub pension 
{
	my ($emp) = @_;
#	return 0 if ($ee{$emp}{pension_amt} == 0 and $ee{$emp}{pension_rate} == 0);
	my $i_401k = 0;
	my $i_max = $VAR{pension};
# additional funding for age
# check if dob in ee file	
#	my $age = $year - substr($ee{$emp}{dob},6);
#	die "FAIL $emp no age\n" unless defined $age;
#	if ($age > $VAR{pension_age}) {$i_max += $VAR{pension_add};}
# first check flat payment
	if ($ee{$emp}{pension_amt} > 0) 
		{$i_401k = $ee{$emp}{pension_amt};}
# percentage payment overwrites flat 
	if ($ee{$emp}{pension_rate} ne 0) 
	{
		my $irate = $ee{$emp}{pension_rate};
		$irate =~ s/\%//g;
		my $iirate = ".$irate";
		$i_401k = ($iirate*$stub{$emp}[$ROW]{gross});
	}
	my $ip = ratio($i_max, $i_401k, $stub{$emp}[$y_ROW]{pension});
	return sprintf("%.2f",$ip);
}
sub addmed
{
	my ($emp, $i_status) = @_;
# most will skip
	return 0 if ($stub{$emp}[$y_ROW]{gross} < $VAR{addmed_s});

	my $i_max; my $iaddmed; 
	# get tax-status
	if($i_status eq ('s' || 'ss')) 
		{$i_max = $VAR{addmed_s};}
	else {$i_max = $VAR{addmed_m};}

	$iaddmed = ratio($i_max,$stub{$emp}[$ROW]{gross},$stub{$emp}[$y_ROW]{gross});

	return (sprintf("%.2f",$VAR{addmed_rate}*$iaddmed));
}
sub stubpdf
{
        my ($icur,$emp) = @_;
	#$emp =~ s%_%, %;
################################
        $icur =~ s%txt%pdf%;
################################
        my $pdf = PDF::API2->new();
        my $page = $pdf->page();
        my $text = $page->text();
################################
	my $lcursor = 750;
	my $wcursor = 25;
	my $rstep =20;
	my $cstep = 40;
        my $font;
        if ($emp eq 'ytd')
		{$page->mediabox((11*72),(8.5*72)); $lcursor = 550;}
	else {$page->mediabox((8.5*72),(11*72));}
# HEADERS ######################
        $font = $pdf->corefont('Courier-Bold');
        $text->fillcolor('black'); $text->font($font,18);
        $text->translate($wcursor,$lcursor); 
	$text->text($year);
################################
        $font = $pdf->corefont('Times-BoldItalic');
        $text->fillcolor('black'); $text->font($font,16);
        $text->translate($wcursor+80,$lcursor); 
	$text->text($company);
################################
        $font = $pdf->corefont('Times-Roman');
        $text->fillcolor('red'); $text->font($font,18);
        $text->translate($wcursor+300,$lcursor); 
	$text->text($emp);
################################
        $font = $pdf->corefont('Times-Roman');
        $text->fillcolor('black'); $text->font($font,12);
        $text->translate($wcursor+450,$lcursor); 
	$text->text($date);
################################
        $font = $pdf->corefont('Times');
        $text->fillcolor('black'); $text->font($font,8);
	my $LC = $lcursor-$rstep;
	my $WC = 25;
        $text->translate($WC,$LC);
################################
	my @scol;
	my @icol = @STUB_COL;
	shift @icol;

	$scol[0] = $STUB_COL[0];
	my $iv = 0;
	for (@icol)
	{
		if ($stub{$emp}[$y_ROW]{$_} > 0)
		{push(@scol, $_);} 
	}
################################
        for (@scol)
        {
		$text->translate($WC,$LC);
		$text->text($_);
		$WC += $cstep;
        }
################################
	my @irow=0..$y_ROW; # pop @irow;
        foreach my $irow (@irow)
        {
		$LC -= $rstep;
		$WC =25;
		$text->translate($wcursor,($LC));
		#foreach my $icol (@STUB_COL)
                foreach my $icol (@scol)
                { 
			$text->translate($WC,$LC);
			$text->text($stub{$emp}[$irow]{$icol});
			$WC += $cstep;
		}
	}
	$pdf->saveas($icur);
}
