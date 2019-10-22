#Requires -Module ActiveDirectory
#Requires -Version 4
<#PSScriptInfo

.VERSION 0.9

.GUID 6daab471-c714-4c2c-a887-bf3eb56567eb

.AUTHOR Chad.Cox@microsoft.com
    https://blogs.technet.microsoft.com/chadcox/
    https://github.com/chadmcox

.COMPANYNAME 

.COPYRIGHT This Sample Code is provided for the purpose of illustration only and is not
intended to be used in a production environment.  THIS SAMPLE CODE AND ANY
RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  We grant You a
nonexclusive, royalty-free right to use and modify the Sample Code and to
reproduce and distribute the object code form of the Sample Code, provided
that You agree: (i) to not use Our name, logo, or trademarks to market Your
software product in which the Sample Code is embedded; (ii) to include a valid
copyright notice on Your software product in which the Sample Code is embedded;
and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and
against any claims or lawsuits, including attorneys` fees, that arise or result
from the use or distribution of the Sample Code..

.TAGS get-adgroup

.LICENSEURI 

.PROJECTURI 

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES
0.9 fixed logic
0.8 Added Progress bar


.DESCRIPTION 
 This script is will gather useful information around ad objects including cleanup task. 

#> 
Param($reportpath = "$env:userprofile\Documents",[switch]$getonlycircularnested)

$DebugPreference = "Continue"

cd $reportpath
$searchbase = @()
$default_err_log = "$reportpath\err.txt"
$time_log = "$reportpath\runtime.csv"

Function createADSearchBase{
    $hash_domain = @{name='Domain';expression={$domain}}
    $searchbase_list = "$reportpath\tmpADSearchBaseList.csv"
    try{Get-ChildItem $searchbase_list | Where-Object { $_.LastWriteTime -lt $((Get-Date).AddDays(-5))} | Remove-Item -force}catch{}
    write-host "Generating Search Base List"
    If (!(Test-Path $searchbase_list)){
        foreach($domain in (get-adforest).domains){
            write-debug "Gathering OUs"
            try{Get-ADObject -ldapFilter "(objectclass=organizationalunit)" `
                -Properties "msds-approx-immed-subordinates" -server $domain -ResultPageSize 500 -ResultSetSize $null | `
                     where {$_."msds-approx-immed-subordinates" -ne 0} | select `
                $hash_domain, DistinguishedName  | export-csv $searchbase_list -append -NoTypeInformation}
            catch{"function CollectionADSearchBase - $domain - $($_.Exception)" | out-file $default_err_log -append}
            try{Get-ADObject -ldapFilter "(objectclass=domainDNS)" `
                -Properties "msds-approx-immed-subordinates" -server $domain -ResultPageSize 500 -ResultSetSize $null | `
                     where {$_."msds-approx-immed-subordinates" -ne 0} | select `
                $hash_domain, DistinguishedName  | export-csv $searchbase_list -append -NoTypeInformation}
            catch{"function CollectionADSearchBase - $domain - $($_.Exception)" | out-file $default_err_log -append}
            try{Get-ADObject -ldapFilter "(objectclass=builtinDomain)" `
                -Properties "msds-approx-immed-subordinates" -server $domain -ResultPageSize 500 -ResultSetSize $null | `
                     where {$_."msds-approx-immed-subordinates" -ne 0} | select `
                $hash_domain, DistinguishedName  | export-csv $searchbase_list -append -NoTypeInformation}
            catch{"function CollectionADSearchBase - $domain - $($_.Exception)" | out-file $default_err_log -append}
            try{(get-addomain $domain).UsersContainer | Get-ADObject -server $domain | select `
                $hash_domain, DistinguishedName | export-csv $searchbase_list -append -NoTypeInformation}
            catch{"function CollectionADSearchBase - $domain - $($_.Exception)" | out-file $default_err_log -append}
            try{(get-addomain $domain).ComputersContainer | Get-ADObject -server $domain | select `
                $hash_domain, DistinguishedName | export-csv $searchbase_list -append -NoTypeInformation}
            catch{"function CollectionADSearchBase - $domain - $($_.Exception)" | out-file $default_err_log -append}
        }
    }
    else{
        Write-host "Reusing Existing Searchbase List"
    }
    $searchbase = import-csv $searchbase_list
    $searchbase
}
Function CollectADNestedGroups{
    $results = @()
    $groups = @()
    $GroupProperties = @("memberof","distinguishedname")
    
    if(!($searchbase)){
            #go to function to populate the variable
            Measure-Command {$searchbase = createADSearchBase} | `
                select @{name='RunDate';expression={get-date -format d}},`
                @{name='Function';expression={"createADSearchBase"}}, `
                @{name='Hours';expression={$_.hours}}, `
                @{name='Minutes';expression={$_.Minutes}}, `
                @{name='Seconds';expression={$_.Seconds}} | export-csv $time_log -append -notypeinformation
    }
    foreach($sb in $searchbase){$domain = $sb.domain
        try{$groups += get-adgroup -ldapFilter "(|(member=*)(memberof=*))" `
                -Properties $groupProperties -SearchBase $sb.distinguishedname -SearchScope OneLevel `
                -Server $sb.domain -ResultPageSize 500 -ResultSetSize $null | select $GroupProperties}
        catch{"functionCollectADComputers - $domain - $($_.Exception)" | out-file $default_err_log -append}
    }
    write-host "Extracting Group Direct Members"
    foreach($group in $groups){
        if($group.memberof){
            $group | Select-Object -ExpandProperty Memberof | foreach {
                $objtmp = new-object -type psobject
                $objtmp | Add-Member -MemberType NoteProperty -Name "group" -Value $group.distinguishedname
                $objtmp | Add-Member -MemberType NoteProperty -Name "memberof" -Value $_
                
            $objtmp
            }
        }
    }

}
function expandADGroupMembership{
    param($groupDN,$originalDN,[switch]$expand)
    <#Links I used to make this
    #http://blogs.msdn.com/b/adpowershell/archive/2009/09/05/token-bloat-troubleshooting-by-analyzing-group-nesting-in-ad.aspx
    #http://www.powershellmagazine.com/2013/11/26/identifying-active-directory-built-in-groups-with-powershell/
    #http://blogs.technet.com/b/heyscriptingguy/archive/2010/07/22/hey-scripting-guy-how-can-i-use-windows-powershell-2-0-to-find-active-directory-domain-services-groups-not-being-used.aspx
    #had a heck of a time with isCriticalSystemObject
    #http://www.jhouseconsulting.com/2015/01/02/script-to-create-an-overview-and-full-report-of-all-group-objects-in-a-domain-1455
    #nice article around powershell parameter validation
    http://blogs.technet.com/b/heyscriptingguy/archive/2011/05/15/simplify-your-powershell-script-with-parameter-validation.aspx
    #>

    write-debug $groupDN
    $script:searchedgroups += $groupDN
    $script:grpsearchedDonotlookfornesting += $groupDN
    #filter where group is same as groupdn loop through all group member of
    $script:groupswithmemberships | Foreach {
        if($_.group -eq $groupDN){
            #is the parent group 
            write-debug "member $(($_).memberof)"
            if($script:searchedgroups -contains $_.memberof){
                if(!($script:identifiedgroup -contains $_.group)){
                    write-debug $True
                    #group already searched
                    if($_.memberof -eq $originalDN){
                        $script:circularnestedgroups += $_
                        $script:identifiedgroup += $_.group
                    }
                }
            }else{
                if($expand){
                    $script:expandedgroups += $_ | select @{Name="group";Expression={$originalDN}},memberof
                    expandADGroupMembership -groupDN $_.memberof -originalDN $originalDN -expand
                }else{
                    expandADGroupMembership -groupDN $_.memberof -originalDN $originalDN}
            }   
        }        
    }
}
function startADGroupExpansion{
    $i = 0
    $script:circularnestedgroups = @()
    $script:othersearchedgroup = @()
    $script:expandedgroups = @()
    $script:groupswithmemberships = @()
    $script:searchedgroups = @()
    $script:grpsearchedDonotlookfornesting = @()
    $script:identifiedgroup = @()
    $script:groupswithmemberships = CollectADNestedGroups | sort
    $groupcount = $(($script:groupswithmemberships.group | select -Unique).count)
    Write-host "Found $groupcount Groups to Expand"
    ($script:groupswithmemberships).group  | select -Unique | sort | foreach{
        Write-Progress -Activity "Building Group Membership" -Status "Group: $($_)" -PercentComplete ($I/$groupcount*100);$i++
            #this basicall determines if I want to only get circular nesting
            if(!($getonlycircularnested)){$script:searchedgroups = @()}
            Write-Debug "--------$($_)------"
            expandADGroupMembership -groupDN $_ -originalDN $_ -expand
    }
    Write-Progress -Activity "Complete" -Status "End" -Completed 
    $script:expandedgroups
}
Function creategroupmemofsummary{
    $groupDirectCount | foreach{$currentgdc = $_
        $groupExpandedCount | foreach{$currentgec = $_
            if($currentgdc.name -eq $_.name){
                    $prob = $(100 - [math]::Round((($currentgec.count - $currentgdc.count) / $currentgec.count) * 100))
                    $currentgdc | select name, `
                        @{name='DirectCount';expression={$_.count}}, `
                        @{name='ExpandedCount';expression={$currentgec.count}},`
                        @{name='LikelyProblem';expression={
                            if(([convert]::ToInt32($currentgec.count) -gt 500 -and  [convert]::ToInt32($prob) -gt 75) -or ([convert]::ToInt32($_.count) -gt 1000)){
                                "Critical"
                            }Elseif([convert]::ToInt32($currentgec.count) -gt 250 -and  [convert]::ToInt32($prob) -gt 50){
                                "High"
                            }elseif([convert]::ToInt32($currentgec.count) -gt 100 -and  [convert]::ToInt32($prob) -gt 35){
                                "Medium"
                            }else{
                                "Low"
                            }}}
            }
        }
    }
}

cls
$results = @()
startADGroupExpansion | export-csv "$reportpath\reportADGroupMembersExpanded.csv" -NoTypeInformation
$script:circularnestedgroups | export-csv "$reportpath\reportADGroupCircularNested.csv" -NoTypeInformation
$script:groupswithmemberships | export-csv "$reportpath\reportADGroupDirectMemberOf.csv" -NoTypeInformation
write-host "Creating Nesting Summary"
$groupDirectCount = $script:groupswithmemberships | Group-Object group | select name, count | sort name
$groupExpandedCount = $script:expandedgroups | Group-Object group | select name, count | sort name

$results = creategroupmemofsummary
$results  | export-csv "$reportpath\reportADGroupMemStats.csv" -NoTypeInformation
write-host "-----------------------------------" -ForegroundColor Yellow
write-host "Groups Likely To Cause a Token Issue Due to Over Nesting" -ForegroundColor Yellow
$results | sort ExpandedCount -Descending | where {$_.LikelyProblem -ne "low"} | select -first 25 | Out-Host
write-host "-----------------------------------" -ForegroundColor Yellow

write-host "Results can be found here: $reportpath\reportADGroupMembersExpanded.csv" 

#$script:expandedgroups | Group-Object group | select name, count | sort count -Descending | select -first 50
