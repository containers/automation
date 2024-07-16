
# Intended to be run like: `gnuplot -p -c Utilization.gnuplot`
# Requires a file named `utilization.csv` produced by commands
# in `Cron.sh`.
#
# Format Ref: http://gnuplot.info/docs_5.5/Overview.html

set terminal png enhanced rounded size 1400,800 nocrop
set output 'html/utilization.png'

set title "Persistent Workers & Utilization"

set xdata time
set timefmt "%Y-%m-%dT%H:%M:%S+00:00"
set xtics nomirror rotate timedate
set xlabel "time/date"
set xrange [(system("date -u -Iseconds -d '26 hours ago'")):(system("date -u -Iseconds"))]

set ylabel "Workers Online"
set ytics border nomirror numeric
# Not practical to lookup $DH_PFX from pw_lib.sh
set yrange [0:(system("grep -E '^[a-zA-Z0-9]+-[0-9]' dh_status.txt | wc -l") * 1.5)]

set y2label "Worker Utilization"
set y2tics border nomirror numeric
set y2range [0:100]

set datafile separator comma
set grid

plot 'utilization.csv' using 1:2                  axis x1y1 title "Workers"     pt 7 ps 2, \
                    '' using 1:((($3-$4)/$2)*100) axis x1y2 title "Utilization" with lines lw 2
