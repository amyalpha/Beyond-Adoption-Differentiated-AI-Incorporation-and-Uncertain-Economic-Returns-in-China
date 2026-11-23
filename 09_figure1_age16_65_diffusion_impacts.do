version 16.0
set more off

/*
    FIGURE 1. RAPID AI DIFFUSION AND PERCEIVED CONSEQUENCES

    Run this file after opening the prepared WIDE dataset. The household
    AI-module variables may have been copied to every person during a
    household-to-person merge. This file restores the questionnaire unit
    by retaining one household AI record separately within each wave.

    Panel A
      Weighted percentages for 2023 AI awareness, 2023 Generative AI use,
      2025 Generative AI use, and 2025 Specialised AI use. Each wave uses
      its own unique household AI-module records and household weights.
      Both waves are restricted to selected respondents aged 16-59 who
      were not engaged in farming, matching the 2025 questionnaire route.

    Panel B
      Weighted percentages selecting each perceived consequence in
      2025, estimated separately among Generative AI and Specialised AI
      users. The consequence question is multiple-response,
      so percentages do not sum to 100.

    Important
      - Generative AI and Specialised AI samples are independent.
      - Person-level duplicates of household AI answers are removed.
      - Household weights, not individual weights, are used.
      - A1013 identifies the respondent whose age and work type define
        eligibility; no arbitrary household member defines the sample.
      - Missing values are never recoded as zero.
      - Existing variables beginning fig1_ are dropped before new
        Figure 1 samples are created.
      - preserve/restore prevents the new Figure 1 variables from
        remaining in the wide dataset after the graphs are produced.
*/


*--------------------------------------------------------------------*
* 0. OUTPUT LOCATION AND CLEANUP
*--------------------------------------------------------------------*

* If project_root is already defined, it is retained.
if `"$project_root"' == "" global project_root "."

global fig1_results "$project_root/results/main_figures"
capture mkdir "$project_root/results"
capture mkdir "$fig1_results"

* Drop Figure 1 variables left by an earlier interrupted run.
capture drop fig1_*

capture graph drop fig1_panel_a
capture graph drop fig1_panel_b
capture graph drop figure1_main


*--------------------------------------------------------------------*
* 1. VERIFY THE WIDE DATA AND CORE VARIABLES
*--------------------------------------------------------------------*

local corevars                                                   ///
    ai_awareness_w23 ai_use_w23 gai_use_w25 pai_use_w25          ///
    hhid pline                                                   ///
    ai_respondent_pline_w23 ai_respondent_pline_w25              ///
    birthyear_w23 birthyear_w25                                  ///
    havejob_w23 havejob_w25                                      ///
    main_work_type_w23 main_work_type_w25                        ///
    household_weight_w23 household_weight_w25

foreach v of local corevars {
    capture confirm variable `v'
    if _rc {
        display as error "Required variable `v' is absent."
        display as error "Open the prepared wide dataset before running Figure 1."
        exit 111
    }
}

display as text "Person rows per household in the open wide data:"
duplicates report hhid

* The household respondent selector must identify exactly one person in
* every household carrying an AI-module response. Never choose a member
* arbitrarily after the 1:m household-to-person merge.
gen byte fig1_resp23 = pline == ai_respondent_pline_w23 if       ///
    !missing(pline, ai_respondent_pline_w23)
gen byte fig1_resp25 = pline == ai_respondent_pline_w25 if       ///
    !missing(pline, ai_respondent_pline_w25)
egen byte fig1_hh_tag0 = tag(hhid)
bysort hhid: egen int fig1_n_resp23 = total(fig1_resp23 == 1)
bysort hhid: egen int fig1_n_resp25 = total(fig1_resp25 == 1)
bysort hhid: egen byte fig1_has_ai23 = max(                   ///
    !missing(ai_awareness_w23) | !missing(ai_use_w23))
bysort hhid: egen byte fig1_has_ai25 = max(                   ///
    !missing(gai_use_w25) | !missing(pai_use_w25))

quietly count if fig1_hh_tag0 == 1 & fig1_has_ai23 == 1 &    ///
    fig1_n_resp23 != 1
if r(N) > 0 {
    display as error r(N) " households with 2023 AI data do not match exactly one A1013 respondent."
    display as error "Verify that A1013 contains the respondent's pline before continuing."
    exit 459
}
quietly count if fig1_hh_tag0 == 1 & fig1_has_ai25 == 1 &    ///
    fig1_n_resp25 != 1
if r(N) > 0 {
    display as error r(N) " households with 2025 AI data do not match exactly one A1013 respondent."
    display as error "Verify that A1013 contains the respondent's pline before continuing."
    exit 459
}

* Validate the four binary diffusion measures.
foreach v in ai_awareness_w23 ai_use_w23 gai_use_w25 pai_use_w25 {
    quietly count if !missing(`v') & !inlist(`v', 0, 1)
    if r(N) > 0 {
        display as text "Note: `v' has " r(N)          ///
            " nonbinary response codes; they will be excluded."
    }
}


*--------------------------------------------------------------------*
* 2. LOCATE THE ITEM-LEVEL 2025 CONSEQUENCE VARIABLES
*--------------------------------------------------------------------*

/*
    The code accepts either:
      t1010a_1_mc ... t1010a_9_mc, or
      t1010a_1_mc_w25 ... t1010a_9_mc_w25,
    and the equivalent t1010b variables.

    Items 1-7 and 9 are graphed. Item 8 (other impact) is excluded
    because it is not substantively comparable without coding its text.
*/

foreach j in 1 2 3 4 5 6 7 9 {
    local gai_item`j' ""
    local pai_item`j' ""

    foreach candidate in t1010a_`j'_mc_w25 t1010a_`j'_mc {
        capture confirm variable `candidate'
        if !_rc & `"`gai_item`j''"' == "" local gai_item`j' `candidate'
    }

    foreach candidate in t1010b_`j'_mc_w25 t1010b_`j'_mc {
        capture confirm variable `candidate'
        if !_rc & `"`pai_item`j''"' == "" local pai_item`j' `candidate'
    }

    if `"`gai_item`j''"' == "" | `"`pai_item`j''"' == "" {
        display as error "The item-level T1010 variables are missing for item `j'."
        display as error "Panel B requires T1010a/T1010b items 1-9 in the wide file."
        display as error "Do not replace them with the grouped impact-category variable."
        exit 111
    }
}

* Validate the item indicators as 0/1 variables.
foreach j in 1 2 3 4 5 6 7 9 {
    foreach v in `gai_item`j'' `pai_item`j'' {
        quietly count if !missing(`v') & !inlist(`v', 0, 1)
        if r(N) > 0 {
            display as text "Note: `v' has " r(N)      ///
                " nonbinary response codes; they will be excluded."
        }
    }
}

local gai_impact_vars `gai_item1' `gai_item2' `gai_item3' ///
    `gai_item4' `gai_item5' `gai_item6' `gai_item7'      ///
    `gai_item9'

local pai_impact_vars `pai_item1' `pai_item2' `pai_item3' ///
    `pai_item4' `pai_item5' `pai_item6' `pai_item7'      ///
    `pai_item9'


*--------------------------------------------------------------------*
* 3. RESTORE ONE HOUSEHOLD AI-MODULE RECORD PER WAVE
*--------------------------------------------------------------------*

preserve

tempfile fig1_hh23 fig1_hh25 fig1_a_data fig1_b_data

* 2023: retain one household questionnaire record. Nonawareness is a
* confirmed nonuse state because the use question was routed after
* awareness; other missing use responses remain missing.
preserve
    keep hhid pline ai_respondent_pline_w23              ///
        birthyear_w23 havejob_w23 main_work_type_w23     ///
        household_weight_w23 ai_awareness_w23 ai_use_w23
    drop if missing(hhid)
    keep if pline == ai_respondent_pline_w23
    sort hhid

    gen double fig1_weight = household_weight_w23
    replace fig1_weight = . if missing(fig1_weight) | fig1_weight <= 0

    gen int fig1_age23 = 2023-birthyear_w23 if          ///
        inrange(2023-birthyear_w23, 0, 100)
    gen byte fig1_nonfarm23 = .
    replace fig1_nonfarm23 = 1 if havejob_w23 == 0
    replace fig1_nonfarm23 = 1 if havejob_w23 == 1 &   ///
        !missing(main_work_type_w23) & main_work_type_w23 != 4
    replace fig1_nonfarm23 = 0 if havejob_w23 == 1 &   ///
        main_work_type_w23 == 4
    gen byte fig1_eligible23 = inrange(fig1_age23, 16, 59) & ///
        fig1_nonfarm23 == 1

    gen byte fig1_awareness23 = ai_awareness_w23        ///
        if inlist(ai_awareness_w23, 0, 1)
    gen byte fig1_gai_use23 = .
    replace fig1_gai_use23 = 0 if fig1_awareness23 == 0
    replace fig1_gai_use23 = ai_use_w23 if              ///
        fig1_awareness23 == 1 & inlist(ai_use_w23, 0, 1)

    keep hhid fig1_weight fig1_eligible23               ///
        fig1_awareness23 fig1_gai_use23
    save `fig1_hh23', replace
restore

* 2025: retain one household questionnaire record with the most complete
* set of AI-use and consequence responses. The questionnaire's own routing
* defines eligibility; no arbitrary household member supplies age or job.
preserve
    keep hhid pline ai_respondent_pline_w25             ///
        birthyear_w25 havejob_w25 main_work_type_w25    ///
        household_weight_w25 gai_use_w25 pai_use_w25    ///
        `gai_impact_vars' `pai_impact_vars'
    drop if missing(hhid)
    keep if pline == ai_respondent_pline_w25
    sort hhid

    quietly count if !missing(gai_use_w25) | !missing(pai_use_w25)
    if r(N) > 2762 {
        display as error "The 2025 Figure 1 respondent pool exceeds 2,762 households."
        display as error "Check the A1013 respondent selector before graphing."
        exit 459
    }

    gen double fig1_weight = household_weight_w25
    replace fig1_weight = . if missing(fig1_weight) | fig1_weight <= 0

    foreach v in gai_use_w25 pai_use_w25                 ///
        `gai_impact_vars' `pai_impact_vars' {
        replace `v' = . if !missing(`v') & !inlist(`v', 0, 1)
    }

    gen int fig1_age25 = 2025-birthyear_w25 if          ///
        inrange(2025-birthyear_w25, 0, 100)
    gen byte fig1_nonfarm25 = .
    replace fig1_nonfarm25 = 1 if havejob_w25 == 0
    replace fig1_nonfarm25 = 1 if havejob_w25 == 1 &   ///
        !missing(main_work_type_w25) & main_work_type_w25 != 4
    replace fig1_nonfarm25 = 0 if havejob_w25 == 1 &   ///
        main_work_type_w25 == 4
    gen byte fig1_eligible25 = inrange(fig1_age25, 16, 59) & ///
        fig1_nonfarm25 == 1

    save `fig1_hh25', replace
restore

display as text "Figure 1 unique-household sample audit:"
preserve
    use `fig1_hh23', clear
    count if fig1_eligible23 == 1 &                    ///
        !missing(fig1_weight, fig1_awareness23)
    display as result "2023 awareness denominator: " r(N)
    count if fig1_eligible23 == 1 &                    ///
        !missing(fig1_weight, fig1_gai_use23)
    display as result "2023 Generative AI-use denominator: " r(N)
restore
preserve
    use `fig1_hh25', clear
    count if fig1_eligible25 == 1 &                    ///
        !missing(fig1_weight, gai_use_w25)
    display as result "2025 Generative AI-use denominator: " r(N)
    count if fig1_eligible25 == 1 &                    ///
        !missing(fig1_weight, pai_use_w25)
    display as result "2025 Specialised AI-use denominator: " r(N)
    count if fig1_eligible25 == 1 & fig1_weight < . &  ///
        gai_use_w25 == 1
    display as result "2025 Generative AI-user impact base: " r(N)
    count if fig1_eligible25 == 1 & fig1_weight < . &  ///
        pai_use_w25 == 1
    display as result "2025 Specialised AI-user impact base: " r(N)
restore


*--------------------------------------------------------------------*
* 4. ESTIMATE PANEL A: DIFFUSION, 2023-2025
*--------------------------------------------------------------------*

tempname post_a post_b

postfile `post_a' byte order str40 measure                  ///
    double percent ci_low ci_high long unweighted_n         ///
    using "`fig1_a_data'", replace

local diffusion_label1 "AI awareness, 2023"
local diffusion_label2 "Generative AI use, 2023"
local diffusion_label3 "Generative AI use, 2025"
local diffusion_label4 "Specialised AI use, 2025"

use `fig1_hh23', clear
local diffusion_vars23 fig1_awareness23 fig1_gai_use23
local k = 0
foreach v of local diffusion_vars23 {
    local ++k
    quietly mean `v' [pweight=fig1_weight] if            ///
        fig1_eligible23 == 1 & !missing(fig1_weight, `v')

    scalar fig1_p  = 100*_b[`v']
    scalar fig1_se = 100*_se[`v']
    scalar fig1_lo = max(0,   fig1_p-1.96*fig1_se)
    scalar fig1_hi = min(100, fig1_p+1.96*fig1_se)

    quietly count if fig1_eligible23 == 1 &             ///
        !missing(fig1_weight, `v')
    scalar fig1_n = r(N)

    local this_label `"`diffusion_label`k''"'
    post `post_a' (`k') (`"`this_label'"')                 ///
        (fig1_p) (fig1_lo) (fig1_hi) (fig1_n)
}

use `fig1_hh25', clear
local diffusion_vars25 gai_use_w25 pai_use_w25
foreach v of local diffusion_vars25 {
    local ++k
    quietly mean `v' [pweight=fig1_weight] if            ///
        fig1_eligible25 == 1 & !missing(fig1_weight, `v')

    scalar fig1_p  = 100*_b[`v']
    scalar fig1_se = 100*_se[`v']
    scalar fig1_lo = max(0,   fig1_p-1.96*fig1_se)
    scalar fig1_hi = min(100, fig1_p+1.96*fig1_se)

    quietly count if fig1_eligible25 == 1 &             ///
        !missing(fig1_weight, `v')
    scalar fig1_n = r(N)

    local this_label `"`diffusion_label`k''"'
    post `post_a' (`k') (`"`this_label'"')             ///
        (fig1_p) (fig1_lo) (fig1_hi) (fig1_n)
}

postclose `post_a'


*--------------------------------------------------------------------*
* 5. ESTIMATE PANEL B: ITEM-LEVEL PERCEIVED CONSEQUENCES
*--------------------------------------------------------------------*

postfile `post_b' byte item byte ai_type str55 consequence ///
    double percent ci_low ci_high long unweighted_n         ///
    using "`fig1_b_data'", replace

local impact_label1 "Improves efficiency and quality"
local impact_label2 "Optimizes workflow and resources"
local impact_label3 "Enhances creativity or innovation"
local impact_label4 "Replaces some repetitive tasks"
local impact_label5 "Increases occupational competition"
local impact_label6 "Requires learning new skills or tools"
local impact_label7 "Changes job content or responsibilities"
local impact_label8 "No significant impact"

* The eighth displayed item is questionnaire option 9.
use `fig1_hh25', clear

forvalues j = 1/8 {
    local gvar : word `j' of `gai_impact_vars'
    local pvar : word `j' of `pai_impact_vars'
    local this_label `"`impact_label`j''"'

    * Generative AI users.
    quietly mean `gvar' [pweight=fig1_weight]             ///
        if fig1_eligible25 == 1 & gai_use_w25 == 1 &    ///
        !missing(fig1_weight, `gvar')

    scalar fig1_p  = 100*_b[`gvar']
    scalar fig1_se = 100*_se[`gvar']
    scalar fig1_lo = max(0,   fig1_p-1.96*fig1_se)
    scalar fig1_hi = min(100, fig1_p+1.96*fig1_se)

    quietly count if fig1_eligible25 == 1 &              ///
        gai_use_w25 == 1 &                               ///
        !missing(fig1_weight, `gvar')
    scalar fig1_n = r(N)

    post `post_b' (`j') (1) (`"`this_label'"')            ///
        (fig1_p) (fig1_lo) (fig1_hi) (fig1_n)

    * Specialised AI users, estimated independently.
    quietly mean `pvar' [pweight=fig1_weight]             ///
        if fig1_eligible25 == 1 & pai_use_w25 == 1 &    ///
        !missing(fig1_weight, `pvar')

    scalar fig1_p  = 100*_b[`pvar']
    scalar fig1_se = 100*_se[`pvar']
    scalar fig1_lo = max(0,   fig1_p-1.96*fig1_se)
    scalar fig1_hi = min(100, fig1_p+1.96*fig1_se)

    quietly count if fig1_eligible25 == 1 &              ///
        pai_use_w25 == 1 &                               ///
        !missing(fig1_weight, `pvar')
    scalar fig1_n = r(N)

    post `post_b' (`j') (2) (`"`this_label'"')            ///
        (fig1_p) (fig1_lo) (fig1_hi) (fig1_n)
}

postclose `post_b'


*--------------------------------------------------------------------*
* 6. DRAW PANEL A
*--------------------------------------------------------------------*

use "`fig1_a_data'", clear

format percent ci_low ci_high %5.1f
gen str8 percent_label = string(percent, "%4.1f") + "%"
gen double label_y = min(percent+3, 106)

forvalues j = 1/4 {
    quietly summarize unweighted_n if order == `j', meanonly
    local n`j' = r(mean)
}

export delimited using                                  ///
    "$fig1_results/Figure1_PanelA_estimates.csv", replace

twoway                                                  ///
    (bar percent order if order == 1,                   ///
        barwidth(.68) color(gs9) lcolor(gs6))           ///
    (bar percent order if order == 2,                   ///
        barwidth(.68) color(navy%65) lcolor(navy))      ///
    (bar percent order if order == 3,                   ///
        barwidth(.68) color(navy) lcolor(navy))         ///
    (bar percent order if order == 4,                   ///
        barwidth(.68) color(maroon%75) lcolor(maroon))  ///
    (rcap ci_low ci_high order, lcolor(black)           ///
        msize(small))                                   ///
    (scatter label_y order, msymbol(none)               ///
        mlabel(percent_label) mlabcolor(black)           ///
        mlabsize(small) mlabposition(12)),               ///
    xlabel(                                             ///
        1 "AI awareness, 2023 (N=`n1')"                ///
        2 "Generative AI use, 2023 (N=`n2')"           ///
        3 "Generative AI use, 2025 (N=`n3')"           ///
        4 "Specialised AI use, 2025 (N=`n4')",         ///
        angle(20) labsize(small))                       ///
    ylabel(0(20)100, angle(horizontal) labsize(small))  ///
    yscale(range(0 110))                                ///
    ytitle("Weighted percent") xtitle("")              ///
    title("A. Rapid AI diffusion, 2023-2025",           ///
        size(medsmall) color(black))                    ///
    legend(off) graphregion(color(white))               ///
    plotregion(color(white)) scheme(s1color)            ///
    name(fig1_panel_a, replace)


*--------------------------------------------------------------------*
* 7. DRAW PANEL B
*--------------------------------------------------------------------*

use "`fig1_b_data'", clear

format percent ci_low ci_high %5.1f
gen double y_position = item + cond(ai_type == 1, -.18, .18)
gen double label_x = percent+1.2
gen str8 percent_label = string(percent, "%4.1f") + "%"

quietly summarize unweighted_n if ai_type == 1, meanonly
local gai_n_min = r(min)
local gai_n_max = r(max)
local gai_n_text "`gai_n_min'"
if `gai_n_min' != `gai_n_max' local gai_n_text "`gai_n_min'-`gai_n_max'"

quietly summarize unweighted_n if ai_type == 2, meanonly
local pai_n_min = r(min)
local pai_n_max = r(max)
local pai_n_text "`pai_n_min'"
if `pai_n_min' != `pai_n_max' local pai_n_text "`pai_n_min'-`pai_n_max'"

export delimited using                                  ///
    "$fig1_results/Figure1_PanelB_estimates.csv", replace

twoway                                                  ///
    (bar percent y_position if ai_type == 1, horizontal ///
        barwidth(.30) color(navy) lcolor(navy))         ///
    (bar percent y_position if ai_type == 2, horizontal ///
        barwidth(.30) color(maroon%75) lcolor(maroon))  ///
    (rcap ci_low ci_high y_position if ai_type == 1,    ///
        horizontal lcolor(navy))                        ///
    (rcap ci_low ci_high y_position if ai_type == 2,    ///
        horizontal lcolor(maroon))                      ///
    (scatter y_position label_x if ai_type == 1,        ///
        msymbol(none) mlabel(percent_label)             ///
        mlabcolor(navy) mlabsize(vsmall) mlabposition(3)) ///
    (scatter y_position label_x if ai_type == 2,        ///
        msymbol(none) mlabel(percent_label)             ///
        mlabcolor(maroon) mlabsize(vsmall) mlabposition(3)), ///
    ylabel(                                             ///
        1 "Improves efficiency and quality"            ///
        2 "Optimizes workflow and resources"           ///
        3 "Enhances creativity or innovation"          ///
        4 "Replaces some repetitive tasks"             ///
        5 "Increases occupational competition"         ///
        6 "Requires learning new skills or tools"      ///
        7 "Changes job content or responsibilities"    ///
        8 "No significant impact",                     ///
        angle(horizontal) labsize(vsmall))              ///
    yscale(reverse range(.5 8.5))                       ///
    xscale(range(0 110))                                ///
    xlabel(0(20)100, labsize(small))                    ///
    xline(0, lcolor(gs8)) yline(4.5, lcolor(gs12)       ///
        lpattern(dash))                                 ///
    xtitle("Weighted percent among users") ytitle("")  ///
    title("B. Perceived consequences of AI use, 2025", ///
        size(medsmall) color(black))                    ///
    legend(order(1 "Generative AI users (N=`gai_n_text')" ///
                 2 "Specialised AI users (N=`pai_n_text')") ///
        rows(1) size(small) region(lcolor(none)))       ///
    note("Multiple responses permitted; percentages do not sum to 100.", ///
        size(vsmall))                                   ///
    graphregion(color(white)) plotregion(color(white))  ///
    scheme(s1color) name(fig1_panel_b, replace)


*--------------------------------------------------------------------*
* 8. COMBINE AND EXPORT FIGURE 1
*--------------------------------------------------------------------*

graph combine fig1_panel_a fig1_panel_b, cols(1)        ///
    imargin(tiny) graphregion(color(white))             ///
    title("Figure 1. AI engagement and perceived consequences", ///
        size(medsmall) color(black))                    ///
    note("Each estimate uses the A1013 household respondent, restricted to ages 16-59 and respondents not engaged in farming in both waves, with the corresponding household weight. Panel B uses separate Generative AI-user and Specialised AI-user samples. Error bars are 95% confidence intervals.", ///
        size(tiny))                                     ///
    xsize(8.5) ysize(10)                                ///
    name(figure1_main, replace)

graph save "$fig1_results/Figure1_rapid_AI_diffusion_impacts.gph", ///
    replace
graph export "$fig1_results/Figure1_rapid_AI_diffusion_impacts.pdf", ///
    replace
graph export "$fig1_results/Figure1_rapid_AI_diffusion_impacts.png", ///
    width(4000) replace

restore

display as result "Figure 1 completed. Files saved in:"
display as result "$fig1_results"
