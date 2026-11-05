//
//  NameGenerationService.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation
import os

struct NameGenerationService: Sendable {

    // MARK: - Configuration

    private static let baseURL = "https://randomuser.me/api/"
    private static let requestTimeout: TimeInterval = 10
    private static let session: URLSession = .shared
    private static let maxNPCcount = AppConfig.npcRange.upperBound
    private static var shuffledList: [String] = []
    
    private static let countryCodes =
    [
        "au","br","ca","ch","de",
        "dk","es","fi","fr","gb",
        "ie","in","mx","nl","no",
        "nz","rs","tr","ua","us",
        "us","us","mx","ca","nz"
    ]

    // MARK: - Public

    static func load() {
        reload()
    }

    static func newList(withCount count: Int) -> [String] {
        defer {
            reload()
        }
        return Array(shuffledList.prefix(upTo: count))
    }

    static func reload() {
        shuffledList = fallbackNames(maxNPCcount)
        Task { do {
            let names = try await getRandomNamesList()
            shuffledList = names
        } catch {
            AppLogger.app.warning("Error retrieving new set of names from api. Reverting to local set.")
        }}
    }

    // MARK: - Private

    private static func getRandomNamesList() async throws -> [String] {
        guard let url = URL(string: baseURL)?.appending(queryItems: [
            URLQueryItem(name: "noinfo", value: nil),
            URLQueryItem(name: "inc", value: "name"),
            URLQueryItem(name: "results", value: String(maxNPCcount)),
            URLQueryItem(name: "nat", value: countryCodes.joined(separator: ","))
        ]) else { throw URLError(.badURL) }

        let request = URLRequest(url: url, timeoutInterval: requestTimeout)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // The API reports outages as {"error": "..."}, which fails this decode and triggers the fallback
        let names = try JSONDecoder()
            .decode(APIResponse.self, from: data)
            .results
            .map { $0.name.first.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Treat a short or partially empty response as a failure.
        guard names.count == maxNPCcount else { throw URLError(.cannotParseResponse) }
        return names
    }

    private struct APIResponse: Decodable {
        struct User: Decodable {
            struct Name: Decodable {
                let first: String
            }
            let name: Name
        }
        let results: [User]
    }

    // MARK: - Fallback

    /// Unique names when `count` fits in the list & random picks w/ repeats beyond that
    private static func fallbackNames(_ count: Int) -> [String] {
        let list = Self.fallbackNames
        if count <= list.count {
            return Array(list.shuffled().prefix(count))
        }
        return (0..<count).compactMap { _ in list.randomElement() }
    }

    private static let fallbackNames: [String] = [
        "Aaliyah", "Aarav", "Aaron", "Abigail", "Adam", "Addison", "Aditya", "Adrian", "Adriana", "Aiko",
        "Aisha", "Akira", "Alan", "Albert", "Alejandro", "Alexander", "Alexis", "Ali", "Alice", "Alicia",
        "Allison", "Alondra", "Alyssa", "Amanda", "Amara", "Amber", "Amelia", "Amir", "Amira", "Amy",
        "Ananya", "Andre", "Andres", "Andrew", "Angela", "Anika", "Anjali", "Anna", "Annie", "Anthony",
        "Anya", "April", "Ari", "Arjun", "Arthur", "Asha", "Ashley", "Audrey", "Austin", "Ava",
        "Avery", "Avi", "Ayana", "Ayo", "Bailey", "Bao", "Barbara", "Beatriz", "Beau", "Bella",
        "Benjamin", "Bennett", "Beth", "Bianca", "Blake", "Bonnie", "Brad", "Bradley", "Brady", "Brandon",
        "Brenda", "Brett", "Brian", "Brianna", "Brittany", "Brooke", "Brooklyn", "Bruce", "Bryan", "Caleb",
        "Calvin", "Cameron", "Camila", "Carl", "Carlos", "Carly", "Carmen", "Carol", "Caroline", "Carson",
        "Carter", "Casey", "Catalina", "Catherine", "Cecilia", "Chad", "Charles", "Charlotte", "Chase", "Chelsea",
        "Chidi", "Chloe", "Christian", "Christina", "Christopher", "Claire", "Clara", "Clayton", "Cody", "Colin",
        "Colton", "Connor", "Cooper", "Courtney", "Craig", "Cristian", "Crystal", "Curtis", "Cynthia", "Daisy",
        "Dakota", "Dale", "Dana", "Daniel", "Daniela", "Danielle", "Dario", "Darius", "David", "Dawn",
        "DeAndre", "Dean", "Deborah", "Deepak", "Dennis", "Derek", "Diego", "Divya", "Dmitri", "Dominic",
        "Donald", "Donna", "Dorothy", "Douglas", "Dustin", "Dylan", "Easton", "Ebony", "Eddie", "Edith",
        "Eduardo", "Edward", "Eitan", "Elaine", "Eleanor", "Elena", "Eli", "Elijah", "Elizabeth", "Ella",
        "Ellie", "Elliot", "Emery", "Emilio", "Emily", "Emma", "Emmett", "Enrique", "Eric", "Erica",
        "Erin", "Esteban", "Ethan", "Eugene", "Evan", "Evelyn", "Everett", "Ezra", "Faith", "Fatima",
        "Felix", "Femi", "Fernando", "Fiona", "Frances", "Francesca", "Frank", "Gabriel", "Gabriela", "Gavin",
        "George", "Georgia", "Gianna", "Gina", "Giovanni", "Gloria", "Grace", "Graham", "Grant", "Gregory",
        "Greta", "Guadalupe", "Hailey", "Hana", "Hannah", "Harold", "Harper", "Harrison", "Harry", "Hassan",
        "Hazel", "Heather", "Heidi", "Helen", "Henry", "Hiro", "Hiroshi", "Holly", "Hope", "Howard",
        "Hudson", "Hunter", "Hyun", "Ian", "Ibrahim", "Imani", "Ines", "Isaac", "Isabel", "Isabella",
        "Isaiah", "Ishaan", "Ivan", "Ivy", "Jabari", "Jack", "Jackson", "Jacob", "Jacqueline", "Jade",
        "Jae", "Jake", "Jalen", "Jamal", "James", "Jamie", "Jamila", "Jane", "Janet", "Jared",
        "Jason", "Jasper", "Javier", "Jeffrey", "Jenna", "Jennifer", "Jeremy", "Jesse", "Jessica", "Jill",
        "Jin", "Joan", "Joanna", "Joaquin", "Joel", "John", "Jonah", "Jonathan", "Jordan", "Jorge",
        "Jose", "Joseph", "Josephine", "Joshua", "Josiah", "Joy", "Juan", "Judith", "Julia", "Julian",
        "June", "Justin", "Kai", "Kaitlyn", "Kaito", "Kalani", "Kamari", "Karen", "Karim", "Kate",
        "Katherine", "Katya", "Kavya", "Kayla", "Keanu", "Keiko", "Keisha", "Keith", "Kelly", "Kendall",
        "Kenji", "Kenneth", "Kevin", "Khalid", "Kimberly", "Kiran", "Kofi", "Kristen", "Kwame", "Kyle",
        "Lance", "Landon", "Laura", "Lauren", "Lawrence", "Layla", "Leah", "Leila", "Leilani", "Leo",
        "Leticia", "Levi", "Liam", "Lillian", "Lily", "Lin", "Lincoln", "Linda", "Linh", "Lisa",
        "Logan", "Luca", "Lucas", "Lucia", "Lucy", "Luis", "Luke", "Lupita", "Lydia", "Madeline",
        "Madison", "Maggie", "Mai", "Malia", "Malik", "Manuel", "Marco", "Margaret", "Mariana", "Marisol",
        "Mark", "Marquis", "Mary", "Mason", "Mateo", "Matthew", "Max", "Meera", "Megan", "Mei",
        "Melissa", "Mia", "Micah", "Michael", "Michelle", "Miguel", "Mila", "Miles", "Milos", "Ming",
        "Minh", "Moana", "Mohammed", "Molly", "Monica", "Morgan", "Mustafa", "Nadia", "Naomi", "Natalia",
        "Natalie", "Natasha", "Nathan", "Neha", "Nia", "Nicholas", "Nicole", "Nikhil", "Nikolai", "Noa",
        "Noah", "Nolan", "Noor", "Nora", "Olivia", "Omar", "Owen", "Pablo", "Paige", "Pamela",
        "Paola", "Parker", "Patricia", "Patrick", "Paul", "Pedro", "Penelope", "Peter", "Peyton", "Philip",
        "Piper", "Priya", "Quinn", "Rachel", "Rafael", "Rahul", "Raj", "Ralph", "Rami", "Ramon",
        "Raul", "Ravi", "Rebecca", "Reese", "Ricardo", "Richard", "Riley", "Robert", "Roberto", "Rodrigo",
        "Rohan", "Rosa", "Rose", "Ruby", "Russell", "Ruth", "Ryan", "Salma", "Samantha", "Sameer",
        "Samir", "Samuel", "Sanjay", "Santiago", "Sarah", "Sasha", "Savannah", "Scarlett", "Scott", "Sean",
        "Sebastian", "Sergio", "Seth", "Shanice", "Sharon", "Silas", "Skylar", "Sofia", "Sophie", "Sora",
        "Soraya", "Spencer", "Stella", "Stephanie", "Steven", "Sunil", "Susan", "Sydney", "Talia", "Tariq",
        "Tatiana", "Taylor", "Theodore", "Thomas", "Tiana", "Timothy", "Tomas", "Travis", "Tyler", "Valentina",
        "Victoria", "Vikram", "Viktor", "Vincent", "Violet", "Walter", "Wei", "Wesley", "William", "Willow",
        "Wyatt", "Ximena", "Yael", "Yasmin", "Yuki", "Yusuf", "Zachary", "Zara", "Zoe", "Zuri"
    ]
}
