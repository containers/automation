
# Intended to be run like: `gnuplot -p -c Utilization.gnuplot`
# Requires a file named `utilization.csv` produced by commands
# in `Cron.sh`.
#
# Format Ref: http://gnuplot.info/docs_5.5/Overview.html

set title "Persistent Workers & Utilization"

set xdata time
set timefmt "%Y-%m-%dT%H:%M:%S+00:00"
set xtics rotate timedate
set xlabel "time/date"
set xrange [(system("date -u -Iseconds -d '6 hours ago'")):(system("date -u -Iseconds"))]

set ylabel "Workers Online"
set ytics border numeric
set yrange [0:10]

set y2label "Worker Utilization"
set y2tics border numeric
set y2range [0:50]

set datafile separator comma
set grid

plot 'utilization.csv' using 1:2 title "# Workers" with points pt 7, \
     '' using 1:($3/$2) axis x1y2 title "Tasks/Worker" with lines lw 2

while GPVAL_SYSTEM_ERRNO==0 {
    system "sleep 30s"
    set xrange [(system("date -u -Iseconds -d '6 hours ago'")):(system("date -u -Iseconds"))]
    set yrange [0:10]
    set y2range [0:50]
    replot
    refresh
}
