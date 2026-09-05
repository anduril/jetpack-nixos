use std::fs::File;
use std::io::{self, BufWriter, Read, Write};

fn show_help() {
    eprintln!("diffblocks A_FILE B_FILE BLOCK_SIZE");
    eprintln!();
    eprintln!("Compare A_FILE against B_FILE in BLOCK_SIZE chunks and");
    eprintln!("print coalesced ranges of differing blocks to stdout, one");
    eprintln!("\"start_block count\" pair per line.");
}

fn main() -> io::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 4 {
        show_help();
        std::process::exit(1);
    }

    let block_size = args[3]
        .parse::<usize>()
        .unwrap_or_else(|_| panic!("Failed to parse {} as integer.", &args[3]));
    assert!(block_size > 0, "BLOCK_SIZE must be positive");

    let mut a = File::open(&args[1])?;
    let mut b = File::open(&args[2])?;

    let mut a_buf = vec![0u8; block_size];
    let mut b_buf = vec![0u8; block_size];

    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());

    let mut block: u64 = 0;
    let mut range_start: Option<u64> = None;
    let mut range_len: u64 = 0;

    loop {
        let n = read_exact_or_eof(&mut a, &mut a_buf)?;
        read_exact_or_eof(&mut b, &mut b_buf)?;
        if n == 0 {
            break;
        }

        if a_buf[..n] != b_buf[..n] {
            match range_start {
                Some(_) => range_len += 1,
                None => {
                    range_start = Some(block);
                    range_len = 1;
                }
            }
        } else if let Some(s) = range_start {
            writeln!(out, "{s} {range_len}")?;
            range_start = None;
        }

        block += 1;
    }

    if let Some(s) = range_start {
        writeln!(out, "{s} {range_len}")?;
    }

    out.flush()?;
    Ok(())
}

/// Reads a full block, or whatever is left at EOF. Returns 0 once nothing
/// remains to read.
fn read_exact_or_eof(f: &mut File, buf: &mut [u8]) -> io::Result<usize> {
    let mut total = 0;
    while total < buf.len() {
        match f.read(&mut buf[total..])? {
            0 => break,
            n => total += n,
        }
    }
    Ok(total)
}
