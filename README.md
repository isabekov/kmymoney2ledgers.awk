# KMyMoney's XML to hledger/beancount journal file converter written in AWK

This AWK script converts transactions listed in a KMyMoney's XML file to transactions printed in the hledger/beancount's
journal format. Multiple transaction splits *are also supported*. Python version can be found here: [kmymoney2ledgers](https://github.com/isabekov/kmymoney2ledgers).

Read the article ["Structure of a KMyMoney XML File"](https://www.isabekov.pro/structure-of-a-kmymoney-xml-file/) to
better understand the multicurrency problem in KMyMoney and how to solve it using this tool paired with hledger/beancount.

Basically, KMyMoney may stay as a user-friendly GUI application for recording transactions.
Auto-completion for payees, ability to easily change the account hierarchy and move transactions from one account
to another are the advantages of KMyMoney. However, generation of multiperiod reports should be done by *hledger*, simply because
it allows multicurrency categories ("expenses" and "income") and can handle currency conversion better than KMyMoney.

Supported features:
- printing account opening information for beancount,
- conversion of transactions for hledger/beancount (multiple splits are also supported),
- transaction/split status ("*" - completed/cleared, "!" - pending),
- printing currency conversion prices for hledger/beancount,
- currency symbols (e.g. "$" instead of "USD") for hledger/beancount,
- tags for hledger/beancount (for beancount tags at split level are commented out since it does support only tags at transaction level).

## Use

    cat [inputfile].kmy | gunzip > [inputfile].xml
    awk -f kmymoney2ledgers.awk [inputfile].xml > [output].journal

The output is written into STDOUT stream, so it has to be redirected into a file with a pipe.

Help:

    awk -v rdac=[value] -v tub=[value] -f kmymoney2ledgers.awk [inputfile].xml > [output].[extension]

    Input flags:
        -v tub=value          If value is 1, then use beancount journal output format.
                              If value is 0 or flag is not specified, then output format is hledger journal.
        -v rdac=value         If value is 1, then replace destination account commodity (currency) with source
                              account commodity. No currency conversion is performed. Recommended option.
                              If value is 0 or flag is not specified, then use currency conversion specified
                              in the transaction split, i. e. how it is displayed in KMyMoney.
        -v cse=value          If value is 1, then currency symbols are enabled (e.g. "$" instead of "USD").
                              If value is 0 or flag is not specified, then currency symbols are not used.

## Examples

    # Beancount output:
    awk -v rdac=1 -v tub=1 -v cse=1 -f kmymoney2ledgers.awk [inputfile].xml > [output].beancount

    # Hledger output:
    awk -v rdac=1 -v tub=0 -v cse=1 -f kmymoney2ledgers.awk [inputfile].xml > [output].journal
    awk -v rdac=1 -v cse=1 -f kmymoney2ledgers.awk [inputfile].xml > [output].journal

    # Default options: rdac=0, tub=0, cse=0, so the following two commands will produce the same output:
    awk -v rdac=0 -v tub=0 -v cse=0 -f kmymoney2ledgers.awk [inputfile].xml > [output].journal
    awk -f kmymoney2ledgers.awk [inputfile].xml > [output].journal

## Use cases

- switching to plain text accounting with hledger/beancount,
- using generated journal file for creating multicurrency financial reports in hledger/beancount.

 This tool solves a problem of preparing financial reports in KMyMoney when multiple currencies are used (expenses in vacations, moving to another country).
 KMyMoney does not support multicurrency expense categories. The currency of an expense category is specified during the category's creation.

 Scenarios for handling multicurrency expense categories:
 1) All expense categories are opened in the base currency during the KMyMoney file creation.
    It is a default behavior since people usually spend money in the base currency.
 2) Some or all expense categories are duplicated in other currencies.
    This has to be done manually for every expense category, e.g. "public transport" category has to be
    created in USD, EUR etc. and named properly using suffixes in the names. The problem with this approach is
    that expenses in the same category but different categories cannot be summed up.

 Default behavior of KMyMoney for scenario 1:

 All expense transactions in a foreign currency account will have a converted value of
 the transaction amount in the base currency for the destination account (expense category).
 KMyMoney will always ask about the conversion rate between foreign and base currency.

 With this tool, **one can stop worrying about the currency of the expense category and ignore conversion rate**,
 since this information will not be used when "rdac" flag is specified. Basically, one would always want to use "rdac" flag while converting a KMyMoney file to ledger.

 Scenario 2 is impractical, since expenses are spread among different currencies and cannot be summed up.

## Multicurrency example:

 Summarize yearly income and expenses by categories at depth level 2 starting with year 2019 by converting all earnings/spendings
 in different foreign currencies into Euros where the exchange rate is inferred from the purchase of foreign currencies in
 the "money" (asset) accounts. With an exception of equity accounts, before spending some amount US Dollars on food,
 a larger amount of US Dollars should be bought using the money in the base currency (EUR).

    cat Finances.kmy | gunzip > Finances.xml
    awk -v rdac=1 -v tub=0 -v cse=1 -f kmymoney2ledgers.awk Finances.xml > Finances.journal
    hledger -f Finances.journal balance --flat -Y -b 2019 --change --depth 2 --invert -X € --infer-value Income Expense

 Perform the same operation, but do not convert foreign currency expenses into the base currency. The food expenses in
 this case will be shown separately in EUR and USD.

    cat Finances.kmy | gunzip > Finances.xml
    awk -v rdac=1 -v tub=0 -f kmymoney2ledgers.awk Finances.xml > Finances.journal
    hledger -f Finances.journal balance --flat -Y -b 2019 --change --depth 2 Income Expense

 Beancount example with fava frontend:

    pip install fava
    cat Finances.kmy | gunzip > Finances.xml
    awk -v rdac=1 -v tub=0 -f kmymoney2ledgers.awk Finances.xml > Finances.beancount
    fava Finances.beancount
    # In internet browser, open http://localhost:5000
