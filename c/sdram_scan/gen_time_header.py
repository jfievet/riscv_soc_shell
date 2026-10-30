import datetime

now = datetime.datetime.now()

header_content = f"""// Auto-generated header file
// Date and time: {now.strftime('%Y-%m-%d %H:%M:%S')}

#ifndef GENERATED_HEADER_H
#define GENERATED_HEADER_H

int generated_year = {now.year};
int generated_month = {now.month};
int generated_day = {now.day};
int generated_hour = {now.hour};
int generated_minute = {now.minute};
int generated_second = {now.second};

#endif // GENERATED_HEADER_H
"""

with open("generated_header.h", "w") as f:
    f.write(header_content)