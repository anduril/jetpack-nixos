use std::fs::File;
use std::io::{self, BufWriter, Read, Seek, SeekFrom, Write};

struct Args {
    a: String,
    b: String,
    bs: u64,
    count: u64,
    a_skip: u64,
    b_skip: u64,
}

fn show_help() {
    eprintln!("diffblocks a=A_FILE b=B_FILE [bs=512] [count=0] [a-skip=0] [b-skip=0]");
    eprintln!();
    eprintln!("Compare A_FILE against B_FILE in bs-sized chunks and print");
    eprintln!("coalesced ranges of differing blocks to stdout, one");
    eprintln!("\"start_block count\" pair per line.");
    eprintln!();
    eprintln!("  a=A_FILE     first file to compare");
    eprintln!("  b=B_FILE     second file to compare");
    eprintln!("  bs=SIZE      block size to compare at, in bytes (default 512)");
    eprintln!("  count=N      stop after N blocks; 0 means compare to EOF (default 0)");
    eprintln!("  a-skip=N     skip N blocks at the start of A_FILE before comparing (default 0)");
    eprintln!("  b-skip=N     skip N blocks at the start of B_FILE before comparing (default 0)");
}

fn parse_args() -> Option<Args> {
    let mut a: Option<String> = None;
    let mut b: Option<String> = None;
    let mut bs: u64 = 512;
    let mut count: u64 = 0;
    let mut a_skip: u64 = 0;
    let mut b_skip: u64 = 0;

    for arg in std::env::args().skip(1) {
        let (key, value) = arg.split_once('=')?;
        match key {
            "a" => a = Some(value.to_string()),
            "b" => b = Some(value.to_string()),
            "bs" => bs = value.parse().ok()?,
            "count" => count = value.parse().ok()?,
            "a-skip" => a_skip = value.parse().ok()?,
            "b-skip" => b_skip = value.parse().ok()?,
            _ => return None,
        }
    }

    if bs == 0 {
        return None;
    }

    Some(Args {
        a: a?,
        b: b?,
        bs,
        count,
        a_skip,
        b_skip,
    })
}

fn main() -> io::Result<()> {
    let args = match parse_args() {
        Some(args) => args,
        None => {
            show_help();
            std::process::exit(1);
        }
    };

    let block_size = args.bs as usize;

    let mut a = File::open(&args.a)?;
    let mut b = File::open(&args.b)?;

    a.seek(SeekFrom::Start(args.a_skip * args.bs))?;
    b.seek(SeekFrom::Start(args.b_skip * args.bs))?;

    let mut a_buf = vec![0u8; block_size];
    let mut b_buf = vec![0u8; block_size];

    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());

    let mut block: u64 = 0;
    let mut range_start: Option<u64> = None;
    let mut range_len: u64 = 0;

    loop {
        if args.count != 0 && block >= args.count {
            break;
        }

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
