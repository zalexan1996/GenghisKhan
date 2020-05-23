# Genghis Khan
$DownloadDirectory = "F:\Courses\Khan Academy"


Function Init-Driver
{
    $Options = new-Object OpenQA.Selenium.Chrome.ChromeOptions
    $Options.AddArgument("no-sandbox")
    $Options.AddArgument("headless")
    
    $Driver = New-Object OpenQA.Selenium.Chrome.ChromeDriver -ArgumentList @([OpenQA.Selenium.Chrome.ChromeDriverService]::CreateDefaultService(), $Options, [System.TimeSpan]::FromMinutes(3))
    $Driver | Write-Output
}



Function Get-CourseList {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)][OpenQA.Selenium.Chrome.ChromeDriver]$Driver
    )
    
    Enter-SeURL -Driver $Driver -Url "https://www.khanacademy.org/"

    # Close the banner if it exists
    $BannerBTN = (Find-SeElement -Driver $Driver -ClassName "_19k9w9vw")
    if ($BannerBTN) {
        $BannerBTN.Click()
    }

    # Click the Course Button
    (Find-SeElement -Driver $Driver -ClassName "_tr38f8i").Click()

    # Get all of the courses
    $Courses = (Find-SeElement -Driver $Driver -ClassName "_dsx40t2")
    Foreach ($Course in $Courses)
    {
        [PSCustomObject]@{
            CourseName=$Course.Text
            CourseURL=$Course.GetProperty("href")
        }
    }
}

Function Get-CourseUnits {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)][OpenQA.Selenium.Chrome.ChromeDriver]$Driver,
        [Parameter(Mandatory=$True)][string]$CourseURL
    )
    
    Enter-SeURL -Driver $Driver -Url "$CourseURL" -ErrorAction SilentlyContinue


    # Get all of the course units
    $Units = (Find-SeElement -Driver $Driver -ClassName "_dwmetq")
    Foreach ($Unit in $Units)
    {
        try {

            if ($Unit.GetAttribute("data-test-id") -like "unit-header") {
                [PSCustomObject]@{
                    UnitName=$Unit.Text
                    UnitURL=$Unit.GetProperty("href")
                }
            }

        } catch [OpenQA.Selenium.StaleElementReferenceException] {
            # I don't know what this means, but the program will still work
        }
    }
}

Function Get-UnitVideos {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)][OpenQA.Selenium.Chrome.ChromeDriver]$Driver,
        [Parameter(Mandatory=$True)][string]$UnitURL
    )
    
    Enter-SeURL -Driver $Driver -Url "$UnitURL" -ErrorAction SilentlyContinue
    $aNames = (Find-SeElement -Driver $Driver -ClassName "_11julsbr").Text

    $VideoLinks = (Find-SeElement -Driver $Driver -TagName "a") | ? {$aNames -contains $_.Text}
    
    Foreach ($Video in $VideoLinks) {
        if (($Video.FindElementsByTagName("span") | ? {$_.GetAttribute("aria-label") -like "Video"})) {
            [PSCustomObject]@{
                VideoName = $Video.Text
                VideoURL = $Video.GetProperty("href")
            }
        }
    }
}


Function Download-Video {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)][OpenQA.Selenium.Chrome.ChromeDriver]$Driver,
        [Parameter(Mandatory=$True)][string]$VideoURL,
        [Parameter(Mandatory=$True)][string]$CourseName,
        [Parameter(Mandatory=$True)][string]$UnitName,
        [Parameter(Mandatory=$True)][string]$VideoName,
        [Parameter(Mandatory=$True)][int]$Index,
        [Parameter(Mandatory=$False)][int]$Attempts=3,
        [Parameter(Mandatory=$False)][Switch]$Force
    )
    
    $VideoName = ($VideoName -split "`n")[0].Split([IO.Path]::GetInvalidFileNameChars()) -join ''
    $DLPath = "$DownloadDirectory\$CourseName\$UnitName\$Index - $VideoName.mp4"

    # Make sure we haven't downloaded the video already unless we're forcing it.
    if (!(Test-Path $DLPath) -or $Force) {

        # Download the video
        Invoke-WebRequest -Uri $VideoURL -Method GET -OutFile $DLPath

        # If we successfully downloaded the video, return $True
        if (Test-Path $DLPath) {
            return $True
        }
    }
    else {
        Write-Verbose "File already exists."
        return $True
    }
   

    return $False

}

Function Get-VideoURL
{    
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)][OpenQA.Selenium.Chrome.ChromeDriver]$Driver,
        [Parameter(Mandatory=$True)][string]$VideoURL,
        [Parameter(Mandatory=$False)][int]$Attempts=3
    )
    
    # Try a maximum of $Attempts times
    for ($t = 0; $t -lt $Attempts; $t++) {
        Write-Verbose "Attempt $t"
        try {
            # Navigate to the current video page
            $Driver.ExecuteScript("window.stop();") | Out-Null
            Write-Verbose "Window stopped"
            if ($VideoURL -like "http://*" -or $VideoURL -like "https://*") {
                Write-Verbose "URL is valid. Begin Navigation"
                Enter-SeURL -Driver $Driver -Url "$VideoURL" -Verbose -ErrorAction SilentlyContinue
                Write-Verbose "Navigation complete"


                # Wait for Khan Academy to downgrade from an embeded YouTube video to their self-hosted mirror.
                for ($s = 0; $s -lt 10; $s++) {
                    Write-Verbose $s
                    Start-Sleep 1
                    
                    Write-Verbose "Search for Video"
                    # Get the video's src
                    $Video = Find-SeElement -Driver $Driver -TagName "video"
                    

                    if ($Video) {
                        Write-Verbose "Video found"
                    
                        $VideoURL = $Video.GetProperty("src")
                        Write-Verbose "Window stopped"

                        # If we parsed out a valid video, return it
                        if ($VideoURL) {
                            Write-Verbose "Trying with $VideoURL"
            
                            # Without this, the browser stays stuck loading the current video and hangs for a few seconds.
                            $Driver.ExecuteScript("window.stop();") | Out-Null
                            Write-Verbose "Window stopped"

                            # Close the video
                            Write-Verbose "Closing Video"
                            (Find-SeElement -Driver $Driver -ClassName "_xrgghrk").Click() | Out-Null
                            Write-Verbose "Video closed"

                            return $VideoURL
                        }
                    }
                }
            }
        }
        catch { Write-Verbose "$t ) An error occured getting a link to the current video..."; Throw $_}
    }
    return ""
}

$Driver = Init-Driver

if ($Driver) {
    $CourseList = Get-CourseList -Driver $Driver

    Foreach ($Course in $CourseList) {
        $Units = Get-CourseUnits -Driver $Driver -CourseURL $Course.CourseURL

        Foreach ($Unit in $Units) {
            $i = 1
            $Videos = Get-UnitVideos -Driver $Driver -UnitURL $Unit.UnitURL
    
            Foreach ($Video in $Videos) {
               Start-Sleep -Seconds 2
               
               Download-Video -Driver $Driver -VideoURL $Video.VideoURL -CourseName $Course.CourseName -UnitName $Unit.UnitName -VideoName $Video.VideoName -Index $i -Verbose
               $i++
            }
        }
    }
}
