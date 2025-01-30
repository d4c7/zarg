

options-M 
options-O 
positional-M 
positional-O


option returns + '=' if has argument
as missing always if option is multi

valid_options=all must options at least 1 ocurrence

valid_positional=positional at least 1 ocurrence

autocompleter =  param autocomplete or parser autocomplete

---

cmd |


if (valid_options)
    positional-#i-autocompleter 

else
    missing+long-options-M + missing+short-options-M


---

cmd -|

missing+short-options-M  + missing+short-options-O

---

cmd --|

missing+long-options-M + missing+long-options-O 

---

cmd -a|

if option is valid:
    if option is flag:
        missing+short-options-M  + missing-short-options-O   
    else
        '=' + missing+short-options-M  + missing-short-options-O

---
cmd --a|

if option is valid:
    if option is flag:
        X
    else
        '='

---
cmd -a=|
cmd --a=|

if option is valid:
    param autocomplete or parser autocomplete

---
cmd -a=1 |
cmd --a=2 |
