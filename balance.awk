function escape_special_characters(str, to_escape_back_slash){
    str = gensub(/&quot;/, "\"", "g", str)
    str = gensub(/&amp;/, "\\&", "g", str)
    str = gensub(/&lt;/, "<", "g", str)
    # Replace HTML-encoded tab with two whitespaces
    str = gensub(/&#x9;/, "  ", "g", str)
    # Replace HTML-encoded carriage return with two whitespaces
    str = gensub(/&#13;/, "  ", "g", str)
    return str
}

function replace_double_space_with_single_space(str){
    return gensub(/  /, " ", "g", str)
}

function evaluate_fraction(val_arr){
    split(val_arr[1], val, "/")
    return (val[2] == 0) ? val[1] : val[1] / val[2]
}

function traverse_account_hierarchy_backwards(child, tub){
    if (acnt_prnt[child] == ""){
        if (acnt_name[child] in AccountRenaming){
            name = AccountRenaming[acnt_name[child]]
        } else {
            name = tub ? gensub(/[[:punct:] ]/, "-", "g", acnt_name[child]) : acnt_name[child]
        }
        return tub ? gensub(/[[:punct:] ]/, "-", "g", name): name
    } else {
        parent_acnt_name = traverse_account_hierarchy_backwards(acnt_prnt[child], tub)
        name = tub ? gensub(/[[:punct:] ]/, "-", "g", acnt_name[child]) : acnt_name[child]
        return parent_acnt_name ":" name
    }
}

function parse_account_full_names(){
   for (id in acnt_name){
       acnt_full_name[id] = traverse_account_hierarchy_backwards(id, tub)
   }
}

function parse_dictionaries(){
   asset_flag = 0
   for (line in f) {
       if (f[line] ~ /<ACCOUNT .*opened.*/) {
           match(f[line], /id="([^"]+)"/, id_arr)
           match(f[line], /name="([^"]*)"/, nm_arr)
           match(f[line], /parentaccount="([^"]*)"/, pa_arr)
           match(f[line], /opened="([^"]*)"/, od_arr)
           match(f[line], /currency="([^"]*)"/, cur_arr)
           match(f[line], /type="([^"]*)"/, type_arr)
           # Double space in account name is not allowed
           acnt_name[id_arr[1]] = replace_double_space_with_single_space(nm_arr[1])
           acnt_name[id_arr[1]] = escape_special_characters(acnt_name[id_arr[1]], 0)
           acnt_prnt[id_arr[1]] = pa_arr[1]
           acnt_opdt[id_arr[1]] = od_arr[1]
           acnt_curr[id_arr[1]] = cur_arr[1]
           acnt_type[id_arr[1]] = type_arr[1]
       }
       if (f[line] ~ /<PAYEE /) {
           match(f[line], /id="([^"]+)"/, pi_arr)
           match(f[line], /name="([^"]*)"/, py_arr)
           payee[pi_arr[1]] = escape_special_characters(py_arr[1], tub)
       }

       if (f[line] ~ /<ACCOUNT .*id="AStd::Asset".*>/) {
           asset_flag = 1
       }

       if (f[line] ~ /<\/ACCOUNT>/) {
           asset_flag = 0
       }
       if ((asset_flag == 1) && (f[line] ~ /<SUBACCOUNT/)){
           match(f[line], /id="([^"]+)"/, sub_id_arr)
           asset_acnts[sub_id_arr[1]] = sub_id_arr[1]
       }
   }
}

function abs(x) {
    return x < 0 ? -x : x
}

BEGIN {
    PROCINFO["sorted_in"] = "@unsorted"
    AccountRenaming["Asset"] = "Assets"
    AccountRenaming["Liability"] = "Liabilities"
    AccountRenaming["Expense"] = "Expenses"

    Categories["12"] = "Income"
    Categories["13"] = "Expense"

    zero_amount_acnts = (z == "") ? 0: z
}{
    # Main loop: read all lines into buffer
    f[i=1] = $0
    while (getline)
        f[++i] = $0
}
END {
    parse_dictionaries()
    parse_account_full_names()

   # Transaction counter
   t = 0
   # Scheduled transactions flag (do not convert them)
   st_flag = 0
   for (x in f) {
       if (f[x] ~ /<SCHEDULED_TX/){
           st_flag = 1
       }
       if (f[x] ~ /<\/SCHEDULED_TX/){
           st_flag = 0
       }
       if ((f[x] ~ /<TRANSACTION /) && (st_flag == 0)){
           # Increment transaction counter
           t++
           # Split counter. It should be reset to zero outside the while-loop.
           c = 0

           match(f[x], /commodity="([^"]+)"/, txn_commodity_arr)
           txn_commodity = txn_commodity_arr[1]

           while(f[x] !~ /<\/TRANSACTION/){ # Till the end of transaction definition.
               if (f[x] ~ /<SPLIT /){
                  g = 0
                  ++c
                  match(f[x], /account="([^"]+)"/, sp_acnt)
                  if (sp_acnt[1] in asset_acnts) {
                      match(f[x], /payee="([^"]+)"/, sp_payee)

                      match(f[x], /shares="([^"]+)"/, shares_arr)
                      if (length(shares_arr) != 0){
                          sp_lst_shares[c] = evaluate_fraction(shares_arr)
                      }

                      match(f[x], /value="([^"]+)"/, value_arr)
                      if (length(value_arr) != 0){
                          sp_lst_val[c] = evaluate_fraction(value_arr)
                      }
                      if (txn_commodity == acnt_curr[sp_acnt[1]]) {
                          balance[sp_acnt[1]] += sp_lst_val[c]
                      } else {
                          balance[sp_acnt[1]] += sp_lst_shares[c]
                      }
                  }
               }
               x++
           }
       }
   }

   print("Account ID| Account |Currency| Balance")
   for (acnt in asset_acnts){
       if ((abs(balance[acnt]) > 0.001) || (zero_amount_acnts == 1)) {
           printf("%s | %s | %s | %9.2f\n", acnt, acnt_full_name[acnt], acnt_curr[acnt], balance[acnt])
       }
   }
}
