+++
date = "2016-06-11T09:58:04-05:00"
title = "Spring Data Rest"
description = "How to leverage Spring Data Rest to build a realistic API"
+++

Spring and Java: the enterprise favorites.

The task is building a simple User Management RESTful API.

Our domain consists of *Accounts*, *Groups* and *Roles*. Here's the break down.

<!--more-->

- Accounts have basic user information: first and last name, username, passwords are stored in ldap elsewhere using the magical [Spring LDAP](http://projects.spring.io/spring-ldap/)  - no need to worry about exposing passwords through the API. Accounts are in a *many-to-many* relationship with Groups.
- Groups contain a name, a code (like a short unique human-readable word), and a verbose description. Groups are in a *many-to-many* relationship with Accounts, but also with Roles. Groups are effectively a set of Roles predefined.
- Roles contain a name, a code and a description. Roles are in a *many-to-many* relationship with Groups.



Spring Data Rest excels at straight up RESTful HTTP APIs. You can imagine the endpoints now, hopefully.

- `/accounts`, `/accounts/{id}`, `/accounts/{id}/groups`
- `/groups`, `/groups/{id}`, `/groups/{id}/accounts`, `/groups/{id}/roles`
- `/roles`, `/roles/{id}`, `/roles/{id}/groups`

These mirror the `GET` routes perfectly, and of course, the other HTTP verb routes, such as `POST|PUT|PATCH` are supported where they make sense.

The code for setting this structure up is simple. There are three [POJOs](https://en.wikipedia.org/wiki/Plain_Old_Java_Object), one for each of the domain models. Because each of those domain models is a POJO, they extend nothing, and only implement `Serializable`. Of course, while they *were* only POJOs, one could argue they are no longer *plain*, because various *annotations* will be required because Spring Data Rest leverages [Spring JPA](http://projects.spring.io/spring-data-jpa/).

The `Account.java` is the star of the show.

~~~
@Entity
@Table(name = "accounts")
public class Account {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer id;

    // Demo fields.
    private String username;
    private String firstname;
    private String lastname;

    /**
     * Many-To-Many relationship for Accounts to Groups (i.e. Membership).
     */
    @ManyToMany
    @JoinTable(
            name = "accounts_groups_map",
            joinColumns = @JoinColumn(name = "account_id", referencedColumnName = "id"),
            inverseJoinColumns = @JoinColumn(name = "group_id", referencedColumnName = "id")
    )
    private List<Group> groups;
~~~

You can see here:

1. A POJO muddied by the wicked annotations.
2. `GenerationType.IDENTITY` was required for our PostgreSQL database, but `GenerationType.AUTO` will work for MySQL (my preferred database).
3. Various demo fields, username, first and last name.
4. The many-to-many mapping between Accounts and Groups using a [join table](https://en.wikipedia.org/wiki/Associative_entity).

`Group.java` mirrors `Role.java` very closely, except in the latter, the relationship is inverted.

```
@Entity
@Table(name = "groups")
public class Group {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private long id;

    private String name;
    private String code;
    private String description;

    @ManyToMany
    @JoinTable(
            name = "accounts_groups_map",
            joinColumns = @JoinColumn(name = "group_id", referencedColumnName = "id"),
            inverseJoinColumns = @JoinColumn(name = "account_id", referencedColumnName = "id")
    )
    private List<Account> accounts;

    @ManyToMany
    @JoinTable(
            name = "groups_roles_map",
            joinColumns = @JoinColumn(name = "group_id", referencedColumnName = "id"),
            inverseJoinColumns = @JoinColumn(name = "role_id", referencedColumnName = "id")
    )
    private List<Role> roles;
```

The same major components are found here, as in `Account.java`. The unique part of this POJO is that it has two many-to-many relationships, one for Accounts (as in, this *Group contains these Accounts*), and one for Roles (as in, this *Group has these Roles*).

Spring Data Rest is incredibly *magical*. There is so little code to do so much heavy lifting. The traditional approach to building a RESTful API is to use the MVC pattern. In particular, Spring Data Rest obviates the need for the Controller to some degree, because it *magically* handles the role of the controller through a special *repository* annotation.

The `AccountsRepository.java` implements `JpaRepository`, but more importantly, uses the Spring Data Rest annotation `RepositoryRestResource`. The abominable name of this annotation is likely because uses of better names already existing. Despite that, the repository annotation accepts a few parameters, setting up the plural-singular relationship with the collection and item versions of the repository. After that, all of the routes listed above instantly get hooked up and are ready to go (for Accounts, anyway - the same is true, provided the `GroupsRepository.java`  and `RolesRepository.java` are also created).

```
@RepositoryRestResource(
        path = "accounts",
        collectionResourceRel = "accounts",
        itemResourceRel = "account"
)
public interface AccountsRepository extends JpaRepository<Account, Long> {
  // ...
}
```

One might wonder, what lies within that `// ...` comment? Spring Data Rest allows easy *search* endpoint creation. For example, `/accounts/search/username?q=`, is a route that returns a collection based on the query string value passed to `q`, based on matching partial *usernames*.

```
// ... within AccountsRepository ...
@RestResource(path = "usernames", rel = "usernames")
Page<Account> findByUsernameContaining(@Param("q") String name, Pageable p);
```

1. The `RestResource` exposes the endpoint to the world, based on the `path` value passed in.
2. The endpoint returns a `Page<Account>`, which allows for easy pagination on the client side simply by consuming HATEOAS links - no need to implement `ResourceSupport` or wrap your domain in `Resource` yourself.
3. `@Param("q")` wires the query string parameter to the Java variable `name`.
4. `Pageable p` handles pagniation and sorting, and is provided to the repository automatically.

The default searching mechanism should not strike one as very powerful, nor generalized. Effectively, this runs `LIKE %username%` through the database and returns whaterver it finds. That is fine, but it might not be enough in all situations.

Spring Data Rest can handle non-RESTful endpoints as well. Suppose, for some reason, you need to occasionally resolve a username to an Account ID. One strategy might be to create a custom endpoint that accepts a username, and returns a `Location` header for the caller to follow to fetch the full account by.
